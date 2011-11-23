class Analyze

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

			enemies = ant.enemies_in_view 

			# Also collect enemies of friends
			friends.each do |f|
				#$logger.info { "Enemies of friend #{ f}: #{ f.enemies_in_view }" }
				enemies += f.enemies_in_view
			end
			enemies.uniq!

			#$logger.info { "Friends of #{ ant }: #{ friends }" }
			$logger.info { "Enemies of #{ ant }: #{ enemies }" }

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

			friends.each do |ant2|
				e = ant2.closest_enemy
				if not e.nil?
					d = Distance.get ant2, e
					if d.in_peril?
						friends_peril << ant2
					else
						friends_close << ant2
					end
				else
					friends_close << ant2
				end
			end

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

				# Need to do some move arbitration here, because adjacent ant can 
				# block each other
				# TODO: ensure that the following loop breaks out on problems
				all_moved = false	# to get in the loop
				until all_moved
					all_moved = true

					ant_combis.each_index do |i|
						ant = ant_combis[i]
						dir = best_dir[0][i]

						next if ant.moved?

						unless dir == :STAY or ant.can_pass? dir
							$logger.info "Ant blocked!"

							if ant.square.neighbor(dir).ant?
								other_ant = ant.square.neighbor(dir).ant
								unless ant_combis.include? other_ant
									$logger.info "Idiot ant in the way; giving up."
									ant.move :STAY
									next
								end
							end

							all_moved = false
							next
						end

						# TODO: this sometimes goes wrong with > 1 ant
						#       incorrection direction in neighbor()
						# Perhaps because :STAY was not handled properly for collectives
						ant.move dir
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


	def self.analyze_hits guess, move
		unless move.kind_of? Array
			move = [ move ]
		end

		# Now, analyze the hits between the ants
		# Note that no distinction is made between various enemies
		enemy_hits = {}
		friend_hits = {}
		sum_dist = 0
		guess.each_index do |e|
			move.each_index do |f|
				dist = Distance.get( guess[e], move[f])
				sum_dist += dist.dist

				#$logger.info "dist: #{ dist }, #{ dist.dist}"
				if dist.in_attack_range?
					#$logger.info "In attack range"
					if enemy_hits[e].nil?
						enemy_hits[e] = [f]
					else
						enemy_hits[e] << f
					end
					if friend_hits[f].nil?
						friend_hits[f] = [e]
					else
						friend_hits[f] << e
					end
				end
			end
		end

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

		moves.each do |item|
			dir  = item[0]
			move = item[1]

			# Skip items in which friends kill each other.
			if move.length != move.uniq.length
				$logger.info "WARNING: friends are killing each other."
				next
			end 

			#$logger.info "Analyzing direction #{ dir }"
			dead = Analyze.analyze_hits guess, move
			$logger.info { "Analyzed: #{ dir }; friends dead: #{ dead[0] }, enemies dead: #{ dead[1] }, best_dist: #{ dead[2] }" }

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
		end

		$logger.info { 
			if best_dir.nil?
				"No best move!"
			elsif count == moves.length
				"All moves are valid"
			else
				"Best moves: #{ best_dir }; friends dead: #{ best_dead[0] }, enemies dead: #{ best_dead[1] }, best_dist: #{ best_dead[2] }"
			end
		}

		[count, best_dir]
	end
end
