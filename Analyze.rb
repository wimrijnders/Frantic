class Array

	def uniq?
		self == self.uniq
	end

end

class Analyze

	@@hits_cache = nil
	@@cache_hits = 0
	@@cache_misses = 0
	@@cache_hits1 = 0
	@@cache_misses1 = 0

	def self.guess_enemy_moves in_enemies, square
		enemies = []
		guess = []
		harmless = true
		in_enemies.each do |e|
			harmless &&= ( e.twitch? or e.stay? )
			enemies << e 

			guess << e.guess_next_pos( square )
		end
		return false if guess.length == 0

		$logger.info { "Enemies guess next pos: #{ guess }" }

		[ harmless, enemies, guess]
	end


	def self.analyze ai

		# Remember who we handled, so we don't re-iterate over them
		# Note that only collective leaders are stored here, not all
		# collective members
		done = []

		ai.my_ants.each do |ant|
			next if ant.collective_follower?
			next if ant.moved?
			next unless ant.attacked?
			next if done.include? ant
		
			ai.turn.check_maxed_out

			friends_danger = []
			friends_peril = []
			friends_close = []		# Not used yet
			enemies_danger = []
			enemies_peril = []		# Not used yet

			# Collect all neighboring ants
			friends = []
			ant.friends.each do |item|
				f = item[0]		# Remove distance info

				next if f.collective_follower?

				friend = nil
				if f.collective_leader?
					c = f.collective
					if c.assembled?( false)
						friend = c 
					else
						# Only handle leader if not assembled.
						friend = f
					end
				else
					friend = f
				end

				# Don't add ants to the core group if too far away
				d = Distance.get friend,ant 
				if d.in_peril?
					friends << friend
					# Only add ants to done list, not collectives
					done << f
				else 
					friends_close << friend
				end
			end
			#$logger.info { "Friends of #{ ant }: #{ friends }" }

			# Make current ant part of the friends group
			if ant.collective_leader?  and ant.collective.assembled?( false)
				friends.insert 0, ant.collective
			else
				friends.insert 0, ant
			end
			# Only add ants to done list, not collectives
			done << ant 


			# Split into fighting ants and ants close by
			friends.each do |ant2|
				found = false
				added = false
				ant2.enemies_in_view.each do |e|
					found = true

					d = Distance.get ant2, e
					if d.in_danger?
						friends_danger << ant2
						enemies_danger << e
						added = true
					elsif d.in_peril?
						friends_peril << ant2
						enemies_peril << e
						added = true
					else
						break
					end
				end
				if found and not added
					# TODO: these ants were already added
					#       to the done-list; they shouldn't be there
					friends_close << ant2
				end
			end


			# Clean up the doubles in the list
			enemies_danger.uniq!
			enemies_peril.uniq!
			enemies_peril -= enemies_danger
			friends_danger.uniq!
			friends_peril.uniq!
			friends_peril -= friends_danger

			$logger.info { "Enemies in danger: #{ enemies_danger }" }
			next if enemies_danger.empty? # No conflict, don't bother analyzing
			$logger.info { "Enemies in peril: #{ enemies_peril }" }
			$logger.info { "Friends in danger: #{ friends_danger }" }
			$logger.info { "Friends in peril: #{ friends_peril }" }
			#$logger.info { "Friends close: #{ friends_close }" }



			#
			# Analyze the attack
			#

			# Note: we are using the coords of the original ants as param
			# Better would be to determine the shortest distance between an
			# enemy and a friend
			# TODO: sort this out.
			harmless, out_enemies, guess = Analyze.guess_enemy_moves enemies_danger, ant.square 


			moves = [] 
			(friends_danger + friends_peril).each do |ant4|
				moves <<  [ ant4, ant4.all_moves( harmless) ]
			end

			# Init the cache
			Analyze.init_hits_cache moves, guess
			#$logger.info { "All possible moves: #{ moves }" }

			# Remove ants from the danger list if they have no 
			# influence on the effect of the conflict
			friends_danger.clone.each do |a|
				unless Analyze.can_kill? a.id
					$logger.info {
						"#{ a } does not influence conflict. " +
						"Removing from danger list."
					}

					friends_danger.delete a
					friends_peril << a
				end
			end
			$logger.info { "Friends in danger post: #{ friends_danger }" }
			$logger.info { "Friends in peril post: #{ friends_peril }" }
			if friends_danger.empty?
				$logger.info { "No friends in danger, not analyzing" }
				next
			end


			# Do the analysis for the fighting ants
			best_moves = Analyze.determine_best_move guess, friends_danger, harmless

			unless best_moves.nil?
				# Select best good move

				# moving around friends in peril to prevent blocking was a bad
				# idea, code ran wild if there were many. So let's not do that.

				# Just pick the first and hope for the best
				best_move = best_moves[0]
				ant_combis = friends_danger

				#
				# Move the ants
				#

				# Doing some move arbitration here, because adjacent ants can 
				# block each other
				all_moved = false	# to get in the loop
				block_count = 0
				until all_moved
					all_moved = true

					prev_was_collective =  false
					move_index = 0
					ant_combis.each_index do |i|
						ant = ant_combis[i]

						move = best_move[move_index + i]

						dir = Distance.get(ant, move).dir
						$logger.info { "dir: #{ dir }" }

						next if ant.moved?

						unless dir == :STAY or ant.can_pass? dir
							$logger.info "#{ant } blocked!"

							if ant.square.neighbor(dir).ant?
								other = ant.square.neighbor(dir).ant
								unless ant_combis.include? other
									$logger.info "Idiot ant in the way; giving up."
									ant.move :STAY
									block_count = 0
									next
								end
							end

							if block_count > 3
								$logger.info "Can't move #{ ant }; giving up."
								ant.move :STAY
								block_count = 0
								next
							end

							all_moved = false
							block_count += 1
							next
						end

						ant.move dir
						block_count = 0

					end
				end
			end

			# Close friend will move in on their own in code downstream
		end
	end


	def self.init_hits_cache movelist, guess
		@@hits_cache = {}
		@@cache_hits = 0
		@@cache_misses = 0
		@@cache_hits1 = 0
		@@cache_misses1 = 0

		# preload the cache with the possible moves
		#$logger.info "movelist: #{ movelist} "
		movelist.each do |moves|
			ant = moves[0]
			moves[1].each_value do |move|
				if move.kind_of? Array
					#$logger.info { "move #{move} is Array" }
					tmp = move
				else
					tmp = [ move ]
				end
				Analyze.get_hits_single ant.id, tmp, guess
			end
		end

		$logger.info {
			str = ""
			@@hits_cache.each_pair do |k,v|
				str2 = ""
				v.each_pair do |k2,v2|
					str2 << "      #{ k2 }=>#{ v2 }\n"
				end
				str << "   #{ k }=> {\n#{ str2 }   }\n"
			end

			"hits_cache: {\n#{ str }}"
		}

		$logger.info { "after preload: #{ hits_cache_status } " }
	end


	def self.killing_friends? ants, result, ants_in_results = true
		#$logger.info "entered"
		list = []
		count = 0

		if ants_in_results 
			ants.each do |ant|
				item = @@hits_cache[ ant.id ][ result[count] ]

				list += item[3]
				count += 1
			end
		else
			$logger.info "ants not in results"

			# Test for ants which are not in the moves list
			# note that they must be in the cache
			ants.each do |ant|
				item = @@hits_cache[ ant.id ][ ant.pos ]

				list += item[3]
				count += 1
			end

			list += result
		end

		#$logger.info { "list: #{ list }" }

		ret = !list.uniq?

		if ret
			$logger.info { "ret: #{ ret }" }
		end

		ret
	end


	def self.hits_cache_status
		"Hits cache: hits/misses single: #{ @@cache_hits }/#{ @@cache_misses }" 
			#"multi: #{ @@cache_hits1 }/#{ @@cache_misses1 }"
	end


	def self.get_hits_single index, moves, guess
		# multiple moves are from collectives
		# Use only the first move as key
		key = moves[0]

		unless @@hits_cache[index].nil? or @@hits_cache[index][key].nil?
			@@cache_hits += 1
			@@hits_cache[index][key]
		else
			@@cache_misses += 1

			enemy_hits = {}
			friend_hits = {}
			sum_dist = 0

		count = 0
		sub_index = 1.0*index
		moves.each do |move|

			guess.each_index do |e|
				dist = Distance.get( guess[e], move)
				sum_dist += dist.dist

				#$logger.info "dist: #{ dist }, #{ dist.dist}"
				if dist.in_attack_range?
					#$logger.info "In attack range"
					if enemy_hits[e].nil?
						enemy_hits[e] = [sub_index]
					else
						enemy_hits[e] << sub_index 
					end
					if friend_hits[sub_index].nil?
						friend_hits[sub_index] = [e]
					else
						friend_hits[sub_index] << e
					end
				end
			end

			#Each move gets its own index
			# Note that there is now a max of 10 
			count += 1
			sub_index += 1.0*count/10 
			raise "Count too large" if count >= 10
		end

		if @@hits_cache[index].nil? 
			@@hits_cache[index] = {}
		end

		# Moves part at end so that we can keep track of followers in collective
		# Note that the key is always in this array
		@@hits_cache[index][key] = [ friend_hits, enemy_hits, sum_dist, moves ]
		end
	end


	# Pre: moves is aray of moves
	def self.get_hits ants, moves, guess
		enemy_hits = {}
		friend_hits = {}
		sum_dist = 0
		moves.each_index do |f|
			ant = ants[f]

			f_hits, e_hits, s_dist = Analyze.get_hits_single ant.id, [ moves[f] ], guess

			enemy_hits.merge!(e_hits)  { |k,oldval,newval| (oldval + newval) }
			friend_hits.merge!(f_hits) { |k,oldval,newval| (oldval + newval) }
			sum_dist += s_dist
		end

		[ friend_hits, enemy_hits, sum_dist ]
	end



	def self.analyze_hits guess, ants, move
		unless move.kind_of? Array
			move = [ move ]
		end

		# Now, analyze the hits between the ants
		# No distinction is made between various enemies
		friend_hits, enemy_hits, sum_dist = Analyze.get_hits ants, move, guess

		return [0,0, sum_dist] if enemy_hits.length == 0
		
		#$logger.info { "enemy hit results: #{ enemy_hits }" }
		#$logger.info { "friend hit results: #{ friend_hits }" }

		# Analyze
		enemy_dead = 0
		friend_dead = 0
		enemy_hits.each_pair do |k,list|
			list.each do |v|
				if list.length >= friend_hits[v].length
					enemy_dead += 1
					break
				end
			end 
		end

		friend_hits.each_pair do |k,list|
			list.each do |v|
				if list.length >= enemy_hits[v].length
					friend_dead += 1 
					break
				end
			end 
		end
		#$logger.info { "Conflict result: dead friends: #{ friend_dead }, " +
		#	"enemies: #{ enemy_dead }, sum_dist: #{ sum_dist}" }

		[ friend_dead, enemy_dead, sum_dist]
	end


	#
	# Determine if this ant has any influence at all
	# in the conflict. If none of its moves hurts the
	# enemy, it has no influence
	#
	def self.can_kill? index
		return false if @@hits_cache[index].nil?

		@@hits_cache[index].each_pair do |k,v|
			if not v[0].empty?
				return true
			end
		end

		false
	end


	#
	# Select moves which do actual damage first.
	#
	def self.hits_bodycount index
		#$logger.info "entered"

		hits = @@hits_cache[index]

		#$logger.info { "hits: #{ hits }" }

		raise "ERROR: hits nil; should never happen!" if hits.nil?

		list = hits.to_a.sort { |aa,bb|
			a = aa[1]
			b = bb[1]

			# damage items first
			if a[0].empty? and not b[0].empty?
				1
			elsif not a[0].empty? and b[0].empty?
				-1
			# After that, sort on smallest distance
			else 
				a[2] <=> b[2]
			end
		}

		# return hurting moves only.
		tmp = list.clone.delete_if { |a| a[1][0].empty? }

		# if no hurting moves present, just return the first move
		if tmp.nil? or tmp.empty?
			list = list[0..0]
		else
			list = tmp
		end

		list = list.collect {|a| a[0] }
		
		$logger.info { "Result: #{ list }" }

		list
	end


	#
	# Select moves which do no damage first.
	#
	def self.hits_safe index
		$logger.info "entered"

		hits = @@hits_cache[index]

		#$logger.info { "hits: #{ hits }" }

		raise "ERROR: hits nil; should never happen!" if hits.nil?

		list = hits.to_a.sort { |aa,bb|
			a = aa[1]
			b = bb[1]

			# Safe items first
			if a[0].empty? and not b[0].empty?
				-1
			elsif not a[0].empty? and b[0].empty?
				1
			# After that, sort on smallest distance
			else 
				a[2] <=> b[2]
			end
		}

		list = list.collect {|a| a[0] }
		
		$logger.info { "Result: #{ list }" }

		list
	end


	def self.iterate_bodycount index, ants, result
		#$logger.info "entered; index #{ index }, ants: #{ ants}, result #{ result }"
		if index == ants.length 
			#$logger.info "yielding #{ result }"
			yield result
			return
		end

		ant = ants[index]

		Analyze.hits_bodycount( ant.id ).each do |h|
			temp = result + [h]
			#$logger.info "temp #{ temp }"

			# Don't handle moves in which friends occupy same square
			next if Analyze.killing_friends? ants[0..index], temp

			Analyze.iterate_bodycount( (index+1), ants, temp ) { |r| yield r }
		end
	end


	def self.iterate_safe index, ants, result, ants_in_results = false
		$logger.info "entered; index #{ index }, ants: #{ ants}, result #{ result }"
		if index == ants.length 
			$logger.info "yielding"
			yield result
			return
		end

		ant = ants[index]

		Analyze.hits_safe( ant.id ).each do |h|
			temp = result + [h]
			#$logger.info "temp #{ temp }"

			# Don't handle moves in which friends occupy same square
			if Analyze.killing_friends? ants[0..index], temp, ants_in_results
				$logger.info "friends are being killed."
				next 
			end

			Analyze.iterate_safe( (index+1), ants, temp, ants_in_results ) { |r| yield r }
		end
	end


	def self.iterate_moves ants
		$logger.info "entered"

		Analyze.iterate_bodycount( 0, ants, [] ) { |r| yield r }

		#moves.each do |item|
		#	yield item[1]
		#end
	end


	def self.ensure_safe ants, moves
		return true if ants.length < 1
		$logger.info "entered; #{ants} - moves #{moves}"

		# Do we have a move conflict?
		tmp = ants.collect { |a| a.pos }
		tmp += moves
		if tmp.uniq?
			$logger.info "No move conflict"
			return true
		end

		# Yes, move the peril ants
		Analyze.iterate_safe( 0, ants, moves ) { |r|
			# Break on the first legal move
			$logger.info "conflict solved: #{ r }"
			return r
		}

		# Bummer; no good moves
		$logger.info "conflict no solution!"
		nil
	end

	def self.play_safe?
		ret = $ai.my_ants.length < AntConfig::ANALYZE_LIMIT

		unless ret
			$logger.info "Ants gonna hurt!" unless @showed_hurt_message
			@showed_hurt_message = true
		end

		ret
	end

	def self.determine_best_move guess, ants, harmless
		# calculate the body count for all possible moves
		# Select the best result
		best_move = nil
		best_dead = nil

		# We have two criteria modes:
		# play hard: aggresive; we concluded that we are superior in this conflict; target is to
		#			 maximize difference between enemy and own casualties
		# play safe: we're not sure we are superior: inflict as much damage as possible while
		#			 minimizing losses.

		num_my_ants = 0
		ants.each do |a|
			if a.kind_of? Collective 
				num_my_ants += a.size
			else
				num_my_ants += 1
			end
		end

		play_hard = !Analyze.play_safe? or
			# We have a numeric advantage
			num_my_ants > guess.length or
			# Enemies are static or twitching pussies
			harmless

		play_safe = !play_hard


		Analyze.iterate_moves( ants ) do |move|
			$logger.info { "move: #{ move }" }

			if move.length != move.uniq.length
				# Should not happen any more; this test is handled elsewhere
				raise "WARNING: friends are killing each other."
			end 

			dead = Analyze.analyze_hits guess, ants, move

			$logger.info {
				"analyzed: friends dead: #{ dead[0] }, " +
				"enemies dead: #{ dead[1] }, " +
				"best_dist: #{ dead[2] }"
			}


			# zero-result territory; it probably won't get any better
			# than this, so stop
			if dead[0] == 0 and dead[1] == 0
				$logger.info "No deaths in this conflict."
				best_move = [move] 
				best_dead = dead
				break
			end

			# If you got 'em all without losing anything, don't 
			# bother looking further
			# Consequence: ants keep moving in the same direction
			# predetermined by order which moves are put in list
			if dead[0] == 0 and dead[1] == guess.length
				$logger.info "Gonna get them all!"
				best_move = [move] 
				best_dead = dead
				break
			end



			if  best_dead.nil? or
				# Maximize the difference in body count
				( play_hard and (best_dead[1] - best_dead[0] ) < ( dead[1] - dead[0] ) ) or
				# Select combination which does damage with least own casualties
				( play_safe and dead[0] < best_dead[0] )

				best_move = [move]
				best_dead = dead
			else 
				if dead[0] == best_dead[0] and dead[1] == best_dead[1] 
					# All things being equal, minimize distance to enemies

					if dead[2] < best_dead[2]
						best_move = [move] 
						best_dead = dead
					elsif dead[2] == best_dead[2]
						best_move << move 
					end
				end
			end

			# Stop on first item which kills enemies without losses when you're a pussy.
			if play_safe and  best_dead[0] == 0 and best_dead[1] > 0
				$logger.info "Killing without being killed"
				break
			end
		end

		if best_dead.nil? or 
			( play_safe and best_dead[0] >= best_dead[1] ) or
			( play_hard and best_dead[0] > best_dead[1] ) 
			$logger.info "Opting for best safe move"

			Analyze.iterate_safe( 0, ants, [], true ) { |r|
				# Break on the first legal move
				$logger.info "safe move: #{ r }"
				best_move = [ r ]
				best_dead = [ 0, 0, -1 ]
				break
			}
		end

		$logger.info {
			str = ""
 
			if best_dead.nil?
				str = "No best move!"
			else
				str = "Best moves: #{ best_move }; friends dead: #{ best_dead[0] }, enemies dead: #{ best_dead[1] }, best_dist: #{ best_dead[2] }"
			end

			str + "\n" + Analyze.hits_cache_status
		}

		best_move
	end
end
