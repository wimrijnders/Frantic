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

	def self.guess_enemy_moves in_enemies
		enemies = []
		guess = []
		harmless = true
		in_enemies.each do |e|
			harmless &&= ( e.twitch? or e.stay? )
			enemies << e 

			guess << e.guess_next_pos
		end
		return false if guess.length == 0

		$logger.info { "Enemies guess next pos: #{ guess }" }

		[ harmless, enemies, guess]
	end


	def self.analyze ai
		done = []
		ai.my_ants.each do |ant|
			next if ant.collective_follower?
			next if ant.moved?
			next unless ant.attacked?
			next if done.include? ant
		
			ai.turn.check_maxed_out

			# Collect all neighboring ants
			friends = []
			ant.friends.each do |item|
				f = item[0]		# Remove distance info

				next if f.collective_follower?

				if f.collective_leader?
					c = f.collective
					if c.assembled?( false)
						friends << c 
					else
						# Only handle leader if not assembled.
						friends << f
					end
				else
					friends << f
				end
			end
			#$logger.info { "Friends of #{ ant }: #{ friends }" }

			# Collect enemies in view of self and near friends
			enemies_in_view = ant.enemies_in_view 

			friends.each do |f|
				#$logger.info { "Enemies of friend #{ f}: #{ f.enemies_in_view }" }
				enemies_in_view += f.enemies_in_view
			end
			enemies_in_view.uniq!
			#$logger.info { "Enemies of #{ ant }: #{ enemies_in_view }" }


			# Make current ant part of the friends group
			if ant.collective_leader?  and ant.collective.assembled?( false)
				friends.insert 0, ant.collective
			else
				friends.insert 0, ant
			end

			# Remember who we handled, so we don'r re-iterate over them
			done += friends

			# Split into fighting ants and ants close by
			friends_danger = []
			friends_peril = []
			friends_close = []		# Not used yet
			enemies_danger = []
			enemies_peril = []		# Not used yet

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

			harmless, out_enemies, guess = Analyze.guess_enemy_moves enemies_danger 

			moves = [] 
			(friends_danger + friends_peril).each do |ant4|
				moves <<  [ ant4, ant4.all_moves( harmless) ]
			end
			#$logger.info { "All possible moves: #{ moves }" }

			# Init the cache
			Analyze.init_hits_cache moves, guess

			# Do the analysis for the fighting ants
			best_moves = Analyze.determine_best_move guess, friends_danger


			unless best_moves.nil?
				# Select the first good move
	
				# 
				# Ensure that peril ants are not blocking
				#
	
				best_move = nil
				ant_combis = friends_danger
				best_moves.each do |m|	
					# Friends in peril should just get out of the way
					ret = Analyze.ensure_safe friends_peril, m

					if ret === true
						# All is well; use current move
						best_move = m
						break
					elsif not ret.nil?
						# Move conflict, but we have a solution
						best_move = m
						ant_combis += friends_peril
						break
					end
				end
				if best_move.nil?
					$logger.info "WARNING: No satisfactory move; using the first"
					best_move = best_moves[0]
				end

				#
				# Move the ants
				#

				# Need to do some move arbitration here, because adjacent ants can 
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
								other_ant = ant.square.neighbor(dir).ant
								unless ant_combis.include? other_ant
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

						# TODO: this sometimes goes wrong with > 1 ant
						#       incorrection direction in neighbor()
						# Perhaps because :STAY was not handled properly for collectives
						ant.move dir
						block_count = 0

					end
				end
			end


if false
			# Move in to help
			friends_close.each do |ant3|
				next if ant3.moved?

				$logger.info { "#{ ant3 } moving in to help" }
				e = ant3.closest_enemy
				unless e.nil?
					# move in to closest enemy
					ant3.move_to e.square
				else
					# Failing that, move in to known enemy
					ant3.move_to enemies[0].square 
				end
			end
		end
end
	end


	def self.init_hits_cache movelist, guess
		@@hits_cache = {}
		@@cache_hits = 0
		@@cache_misses = 0
		@@cache_hits1 = 0
		@@cache_misses1 = 0

		# preload the cache with the possible moves
		$logger.info "movelist: #{ movelist} "
		movelist.each do |moves|
			ant = moves[0]
			moves[1].each_value do |move|
				if move.kind_of? Array
					$logger.info { "move #{move} is Array" }
					tmp = move
				else
					tmp = [ move ]
				end
				Analyze.get_hits_single ant.id, tmp, guess
			end
		end

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
		"Hits cache: hits/misses single: #{ @@cache_hits }/#{ @@cache_misses }; " +
			"multi: #{ @@cache_hits1 }/#{ @@cache_misses1 }"
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
		$logger.info { "Conflict result: dead friends: #{ friend_dead }, " +
			"enemies: #{ enemy_dead }, sum_dist: #{ sum_dist}" }

		[ friend_dead, enemy_dead, sum_dist]
	end


	#
	# Select moves which do actual damage first.
	#
	def self.hits_bodycount index
		$logger.info "entered"

		hits = @@hits_cache[index]

		$logger.info { "hits: #{ hits }" }

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

		$logger.info { "hits: #{ hits }" }

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
		$logger.info "entered; index #{ index }, ants: #{ ants}, result #{ result }"
		if index == ants.length 
			$logger.info "yielding"
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


	def self.iterate_safe index, ants, result
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
			if Analyze.killing_friends? ants[0..index], temp, false
				$logger.info "friends are being killed."
				next 
			end

			Analyze.iterate_safe( (index+1), ants, temp ) { |r| yield r }
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
			$logger.info "conflict solved: #{ result}"
			return result
		}

		# Bummer; no good moves
		$logger.info "conflict no solution!"
		nil
	end


	def self.determine_best_move guess, ants
		# calculate the body count for all possible moves
		# Select the best result
		best_move = nil
		best_dead = nil


		Analyze.iterate_moves( ants ) do |move|
			$logger.info { "move: #{ move }" }

			if move.length != move.uniq.length
				# Should not happen any more; this test is handled elsewhere
				raise "WARNING: friends are killing each other."
			end 

			dead = Analyze.analyze_hits guess, ants, move

			$logger.info {
				"Analyzed #{move}: friends dead: #{ dead[0] }, enemies dead: #{ dead[1] }, " +
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
			# Not really a good idea, ants keep moving in the same direction
			# predetermined by order which moves are put in list
			if dead[0] == 0 and dead[1] == guess.length
				$logger.info "Gonna get them all!"
				best_move = [move] 
				best_dead = dead
				break
			end

			if  best_dead.nil? or
				# Maximize the difference in body count
				( (best_dead[1] - best_dead[0] ) < ( dead[1] - dead[0] ) ) or
				( dead[0] < best_dead[0] )

				best_move = [move]
				best_dead = dead
			else 
				if dead[0] == best_dead[0] and dead[1] == best_dead[1] 
					# All things being equal, minimize distance to enemies

					#$logger.info { "dead[2] < best_dead[2]: #{ dead[2] } < #{ best_dead[2] } =  #{ dead[2] < best_dead[2] }" }

					if dead[2] < best_dead[2]
						best_move = [move] 
						best_dead = dead
					elsif dead[2] == best_dead[2]
						best_move << move 
					end
				end
			end

			# Stop on first item which kills enemies without losses
			# This kind of invalidates this loop, never mind. This loop
			# needs to be optimized badly
			if best_dead[0] == 0 and best_dead[1] > 0
				$logger.info "Killing without being killed"
				break
			end
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
