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
						friends << f
					end
				else
					friends << f
				end
			end

			enemies_in_view = ant.enemies_in_view 

			# Also collect enemies of friends
			friends.each do |f|
				#$logger.info { "Enemies of friend #{ f}: #{ f.enemies_in_view }" }
				enemies_in_view += f.enemies_in_view
			end
			enemies_in_view.uniq!

			#$logger.info { "Friends of #{ ant }: #{ friends }" }
			$logger.info { "Enemies of #{ ant }: #{ enemies_in_view }" }

			if ant.collective_leader?  and ant.collective.assembled?( false)
				friends.insert 0, ant.collective
			else
				friends.insert 0, ant
			end

			# TODO: for collectives, add the individual ants
			done += friends

			# Split into fighting ants and ants close by
			friends_peril = []
			friends_close = []
			enemies = []

			friends.each do |ant2|
				found = false
				in_peril = false
				ant2.enemies_in_view.each do |e|
					found = true

					d = Distance.get ant2, e
					if d.in_peril?
						friends_peril << ant2 unless in_peril
						enemies << e
						in_peril = true
					else
						break
					end
				end
				if found and not in_peril
					friends_close << ant2
				end
			end

			enemies.uniq!
			friends_peril.uniq!

			$logger.info { "Enemies in peril: #{ enemies }" }
			$logger.info { "Friends in peril: #{ friends_peril }" }
			$logger.info { "Friends close: #{ friends_close }" }



			#
			# Analyze the attack
			#
			next if friends_peril.empty?

			harmless, out_enemies, guess = Analyze.guess_enemy_moves enemies 

			moves = [] 
			friends_peril.each do |ant4|
				moves <<  [ ant4, ant4.all_moves( harmless) ]
			end
			#$logger.info { "All possible moves: #{ moves }" }

			# Try all possible combinations
			ant_combis= []
			combinations = []
			moves.each do |m|
				# Following happened if ant/collective was stuck and staying was 'not an option'.
				# Now :STAY is added when no other moves valid, but this safeguard is included
				# just to be pedantically sure
				next if m[1].empty?

				ant = m[0]
				ant_combis << ant
				if combinations.empty?
					m[1].each_pair do |dir, sq |
						unless sq.kind_of? Array
							sqs = [sq]
						else
							sqs = sq
						end
						combinations  << [ [ dir ], sqs ]
					end
				else
					new_combis = []
					combinations.each do |c|
						m[1].each_pair do |dir, sq |
							unless sq.kind_of? Array
								sqs = [sq]
							else
								sqs = sq
							end

							new_combis << [ c[0] + [dir], c[1] + sqs]
						end
					end

					combinations = new_combis
				end
			end
			#$logger.info { "All combinations for #{ ant_combis }: #{ combinations }" }

			count, best_dir = Analyze.determine_best_move guess, combinations
			unless best_dir.nil?
				# Select the first move

				# Need to do some move arbitration here, because adjacent ants can 
				# block each other
				all_moved = false	# to get in the loop
				block_count = 0
				until all_moved
					all_moved = true

					ant_combis.each_index do |i|
						ant = ant_combis[i]
						dir = best_dir[0][i]

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

							if block_count > 10
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


	def self.init_hits_cache movelist, guess
		@@hits_cache = {}
		@@cache_hits = 0
		@@cache_misses = 0
		@@cache_hits1 = 0
		@@cache_misses1 = 0

		# TODO: load possible moves per ant instead of all combinations here below

		# preload the cache with the possible moves
		#$logger.info "guess: #{ guess} "
		#$logger.info "movelist: #{ movelist} "
		movelist.each do |item|
			moves = item[1]
			moves.each_index do |i|
				move = moves[i]

				Analyze.get_hits_single i, [ move ], guess
			end
		end

		$logger.info { "after preload: #{ hits_cache_status } " }
	end


	def self.hits_cache_status
		"Hits cache: hits/misses single: #{ @@cache_hits }/#{ @@cache_misses }; " +
			"multi: #{ @@cache_hits1 }/#{ @@cache_misses1 }"
	end


	def self.get_hits_single index, moves, guess
		unless @@hits_cache[index].nil? or @@hits_cache[index][moves].nil?
			@@cache_hits += 1
			@@hits_cache[index][moves]
		else
			@@cache_misses += 1

			enemy_hits = {}
			friend_hits = {}
			sum_dist = 0

		moves.each do |move|
			guess.each_index do |e|
				dist = Distance.get( guess[e], move)
				sum_dist += dist.dist

				#$logger.info "dist: #{ dist }, #{ dist.dist}"
				if dist.in_attack_range?
					#$logger.info "In attack range"
					if enemy_hits[e].nil?
						enemy_hits[e] = [index]
					else
						enemy_hits[e] << index 
					end
					if friend_hits[index].nil?
						friend_hits[index] = [e]
					else
						friend_hits[index] << e
					end
				end
			end
		end

			if @@hits_cache[index].nil? 
				@@hits_cache[index] = {}
			end

			@@hits_cache[index][moves] = [ friend_hits, enemy_hits, sum_dist ]
		end
	end


	def self.get_hits2 index, moves, guess
		unless @@hits_cache[index].nil? or @@hits_cache[index][moves].nil?
			@@cache_hits1 += 1
			@@hits_cache[index][moves]
		else
			@@cache_misses1 += 1

			if moves.length == 1
				return Analyze.get_hits_single index, moves, guess
			end 

			enemy_hits = {}
			friend_hits = {}
			sum_dist = 0

			f_hits, e_hits, s_dist = Analyze.get_hits index, moves[0..-2], guess
			enemy_hits.merge! e_hits
			friend_hits.merge! f_hits
			sum_dist += s_dist

			f_hits2, e_hits2, s_dist2 = Analyze.get_hits_single (index + moves.length() -1), [ moves[-1] ], guess
			enemy_hits.merge!(e_hits2)  { |k,oldval,newval| (oldval + newval) }
			friend_hits.merge!(f_hits2) { |k,oldval,newval| (oldval + newval) }
			sum_dist += s_dist2

			if @@hits_cache[index].nil? 
				@@hits_cache[index] = {}
			end

			@@hits_cache[index][moves] = [ friend_hits, enemy_hits, sum_dist ]
		end
	end


	def self.get_hits index, moves, guess
		enemy_hits = {}
		friend_hits = {}
		sum_dist = 0
		moves.each_index do |f|
			f_hits, e_hits, s_dist = Analyze.get_hits_single f, [ moves[f] ], guess

			enemy_hits.merge!(e_hits)  { |k,oldval,newval| (oldval + newval) }
			friend_hits.merge!(f_hits) { |k,oldval,newval| (oldval + newval) }
			sum_dist += s_dist
		end

		[ friend_hits, enemy_hits, sum_dist ]
	end



	def self.analyze_hits guess, move
		unless move.kind_of? Array
			move = [ move ]
		end

		# Now, analyze the hits between the ants
		# No distinction is made between various enemies
		friend_hits, enemy_hits, sum_dist = Analyze.get_hits 0, move, guess

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


	def self.determine_best_move guess, moves
		# calculate the body count for all possible moves
		# Select the best result
		best_dir = nil
		best_dead = nil
		count = 0

		# Throw the list around a bit
		#moves = moves.sort_by { rand }

		# Init the cache
		Analyze.init_hits_cache moves, guess

		moves.each do |item|
			dir  = item[0]
			move = item[1]

			# Skip items in which friends kill each other.
			if move.length != move.uniq.length
				#$logger.info "WARNING: friends are killing each other."
				next
			end 

			dead = Analyze.analyze_hits guess, move

			$logger.info {
				"Analyzed: #{ dir }; friends dead: #{ dead[0] }, enemies dead: #{ dead[1] }, " +
				"best_dist: #{ dead[2] }"
			}

			# If you got 'em all without losing anything, don't 
			# bother looking further
			# Not really a good idea, ants keep moving in the same direction
			# predetermined by order which moves are put in list
			if dead[0] == 0 and dead[1] == guess.length
				$logger.info "Gonna get them all!"
				best_dir = [dir]
				best_dead = dead
				count = 1
				break
			end

			if  best_dir.nil? or
				# Maximize the difference in body count
				( (best_dead[1] - best_dead[0] ) < ( dead[1] - dead[0] ) ) or
				( dead[0] < best_dead[0] )

				best_dir = [dir]
				best_dead = dead
				count = 1
			else 
				if dead[0] == best_dead[0] and dead[1] == best_dead[1] 
					# All things being equal, minimize distance to enemies

					#$logger.info { "dead[2] < best_dead[2]: #{ dead[2] } < #{ best_dead[2] } =  #{ dead[2] < best_dead[2] }" }

					if dead[2] < best_dead[2]
						best_dir = [dir]
						best_dead = dead
						count = 1
					elsif dead[2] == best_dead[2]
						best_dir << dir
						count += 1
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
 
			if best_dir.nil?
				str = "No best move!"
			elsif count == moves.length
				str = "All moves are valid"
			else
				str = "Best moves: #{ best_dir }; friends dead: #{ best_dead[0] }, enemies dead: #{ best_dead[1] }, best_dist: #{ best_dead[2] }"
			end

			str + "\n" + Analyze.hits_cache_status
		}

		[count, best_dir]
	end
end
