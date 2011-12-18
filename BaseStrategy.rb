
class BaseStrategy

	# Default implementation does nothing
	def default_move ai
	end


	def self.target_ants ants, from_r, paths, all_ants
		# Now, determine which ants are in the found regions
		antlist = []
		ants.each do |ant|
			unless all_ants
				next if ant.collective?
			end

			paths.each do |path|
				if path.length == 0
					antlist << ant if from_r == ant.square.region
				else
					antlist << ant if path[-1] == ant.square.region
				end
			end
		end

		$logger.info {
			"target_ants found: " + antlist.join(", ")
		}

		antlist.uniq
	end

	#
	# Determine which ants are within a reasonable
	# striking distance of given square
	#
	def self.nearby_ants_region sq, ants, all_ants = false, max_length = nil, do_search = false
		$logger.info "called. max_length: #{ max_length}"

		sq_ants = Region.ants_to_squares ants

		antlist = []

		# Note that the search is actually back to front, from food
		# to ants. The distance of course is the same
		paths = nil
		result = $region.get_neighbors_sorted sq, ants, do_search, max_length

		if result.length > 0
			# Remove distance info
			result.each { |l| antlist << l[0] }
		end

		antlist
	end


	def self.closest_ant_region sq, ai
		antlist = nearby_ants_region sq, ai.my_ants

		# Due to the tests on moved and collective, it is possible that
		# the list is empty
		return nil if antlist.nil? or antlist.length == 0

		# Closest ant is first in list (list is sorted ascending by distance)
		best_ant = antlist[0]
		$logger.info { "best ant: #{ best_ant}" }

		best_ant
	end


	def find_food ai

		count = 0
		ai.food.each do |l|

			sq = ai.map[ l.row ][ l.col ]

			unless l.should_forage? 
				$logger.info { "Skipping food search for #{ sq.to_s }" }
				next
			end

			count += 1
			if count > AntConfig::FOOD_LIMIT
				$logger.info { "Hit limit for foraging; did #{ count - 1 }" }
				break
			end

			l.reset

			ai.turn.check_maxed_out

	
			$timer.start( :closest_ant_region ) {
				ant = ai.nearest_view l.square

				unless ant.nil?
					# Food is in view; check if still there
					if l.square.food?
						if ant.pos.neighbor? l.square
							$logger.info { "#{ ant } right next to food #{ l.square }; just staying put." }
							ant.stay
						else
							if ant.set_order sq, :FORAGE
								l.add_ant ant
							end
						end
					else
						# TODO: Check if this is ever reached
						$logger.info { "Food #{ l.square } gone." }
						ai.food.remove [ l.square.row, l.square.col ]
					end
				end
			}
		end 
	end

	def evade ai
		$logger.info "=== Evade Phase ==="
		ai.my_ants.each do |ant|
			next if ant.moved?
			ai.turn.check_maxed_out

			ant.evading
		end
	end
	

	#
	# return true if move selected this turn; :STAY counts as a move
	#
	def move_neighbors list
		ant = list[-1]

		return false if ant.moved?

		if ant.collective_assembled?
			return false unless ant.collective.disband_if_stuck
		end

		return false if ant.collective_leader?

		$ai.turn.check_maxed_out

		move = ant.next_move
		$logger.info { "#{ant } move #{ move } " }
		unless [true, false].include? move
			if ant.handle_orders false
				$logger.info { "#{ ant } handle_orders succeeded" }
				return true
			end

			# perhaps the other ant is moving in the opposite direction,
			# or going nowhere in particular.
			# If so, we can exchange the orders
			ant2 = ant.square.neighbor(move).ant
			if not ant2.nil? and ant2.mine? and not ant2.moved? and
			 ( [ true, false].include? ant2.next_move or
				ant2.next_move == reverse(move) )

				$logger.info { "ant2 #{ ant2 } next move: #{ ant2.next_move }" }
				if ant2.collective_assembled?
					unless ant2.collective.disband_if_stuck
						$logger.info  "Not exchanging for collective members" 
						return false
					end
				end

				if ant.orders? and ant2.orders? and
				   ant.orders[0] == ant2.orders[0]
					$logger.info "Orders are the same; giving up"
					return false
				end

				# Note that any sorts for both ants are now off by one
				# This will be cumulative for multiple sorts
				# We might have also reached our targets, you never know....
				$logger.info { "Exchanging #{ ant } and #{ ant2}" }
				ant.square, ant2.square = ant2.square, ant.square

				ant.square.ant = ant
				ant.evade_reset
				ant.clear_next_move
				ant.clear_targets_reached

				ant2.square.ant = ant2
				ant2.evade_reset
				ant2.clear_next_move
				ant2.clear_targets_reached


				# Now, redo movement with new ant

				# NOTE: recursive call; better watch stack depth
				list.pop
				list << ant2
				$logger.info { "Redoing move with #{ ant2}" }
				return 	move_neighbors list
			end
		else
$logger.info { "4" }
			# Move is open, try anything
			[ :N, :E, :S, :W ].each do |dir|
				if ant.move dir, nil, false
					$logger.info { "#{ ant } move #{ dir } succeeded" }
					return true
				end
			end
		end
$logger.info { "5" }


		# No decent moves...
		$logger.info { "#{ ant } fail" }

		if $ai.turn.maxed_out?
			ant.stay
			$logger.info { "#{ ant } staying, maxed out" }
			return true
		end


		moves = []
		unless [true, false].include? move
			# Continue in the order direction
			moves << move
		else
			# select neighbor squares  with unmoved ants
			[ :N, :E, :S, :W ].each do |dir|
				n = ant.square.neighbor( dir )
				if n.land? and not n.moved_here? and n.ant? and n.ant.mine? and not n.ant.moved?
					moves << dir
				end
			end
		end

		if moves.empty?
			# give up
			ant.stay
			$logger.info { "#{ ant } staying, no moves" }
			return true
		end

		done_dir = nil
		moves.each do |dir|
			ant2 = ant.square.neighbor( dir ).ant
			next if ant2.nil? or list.include? ant2	# Avoid loops
		
			$logger.info "Recursing with #{ ant2 } 	to #{ dir }"
			if move_neighbors list + [ ant2 ]	
				done_dir = dir
				break	
			end
		end


		# Try moving current ant again
		if done_dir
			if ant.move done_dir, nil, false
				$logger.info { "#{ ant } move #{ done_dir } succeeded on retry" }
				return true
			end
		end

		false
	end


	def ant_orders ai
		ai.my_ants.each do |ant|
			next unless ant.orders?
			# Following are needed, even if they also star in move_neighbors
			next if ant.moved?
			next if ant.collective_leader?

			if not move_neighbors [ant]
				$logger.info "move_neighbors top level fail"
				# Perhaps this helps to alleviate the pain 
				# for the rest of the crowd.
				ant.clear_first_order

				#$logger.info "Forcing handle_orders"
				#ant.handle_orders true
			end
		end
	end


	#
	# Determine which ants are being attacked
	#
	def check_attacked ai
		ai.my_ants.each do |ant|
			ant.check_attacked
		end
	end



	def turn ai, do_orders = true, do_food = true
		evade ai
		find_food ai  if do_food

		$logger.info "=== Default Move Phase ==="
		ai.my_ants.each do |ant|
			next if ant.moved?
			# DON'T EVER PUT FOLLOWING BACK!
			# Ants need to be able to access default moves, even 
			# if they do have orders, in order to get the next border liaison.
			#next if ant.orders?
			next if ant.collective?
			next if ant.harvesting?
			next if ant.orders?

			ai.turn.check_maxed_out

			default_move ant
		end

		if do_orders
			ai.my_ants.each do |ant|
				ant.clear_targets_reached	
			end
			ant_orders ai
		end
	end
end
