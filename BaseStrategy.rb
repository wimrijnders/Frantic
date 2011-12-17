
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
	

	def move_neighbors list
		ant = list[-1]

		return false if ant.moved?
		return false if ant.collective_leader?

		$ai.turn.check_maxed_out

		if ant.stuck?
			if $ai.turn.maxed_out?
				ant.stay
				return false
			end

			[ :N, :E, :S, :W ].each do |dir|
				ant2 = ant.square.neighbor( dir ).ant
				if ant2 and
				   ant2.mine? and
				   not ant2.moved? and
				   not list.include? ant2
			
					if move_neighbors list + [ ant2 ]	
						ant.handle_orders
						return true
					end
				end
			end
		end

		if not ant.stuck?
			ant.handle_orders
			return true 
		end

		false
	end

	def ant_orders ai
		ai.my_ants.each do |ant|
			move_neighbors [ant]
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
