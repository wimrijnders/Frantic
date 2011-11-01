
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
	def self.nearby_ants_region sq, ants, all_ants = false
		$logger.info "called"

		sq_ants = Region.ants_to_squares ants

		antlist = []

		# Note that the search is actually back to front, from food
		# to ants. The distance of course is the same
		paths = nil
		#if all_ants
			# Do a cache search only - we rely on the backburner thread
			# to find the paths for us. 
			result = $region.get_neighbors_sorted sq, ants

			if result.length > 0
				# Remove distance info
				result.each { |l| antlist << l[0] }
			end
		#else
		#	path = Pathinfo.shortest_path sq, sq_ants
		#	unless path.nil?
		#		antlist = BaseStrategy.target_ants ants, sq.region, [path], all_ants
		#	end
		#end

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
		$timer.start "find_food"
		$logger.info "=== Food Phase ==="

		ai.food.each do |l|
			sq = ai.map[ l.row ][ l.col ]

			unless l.should_forage? 
				$logger.info { "Skipping food search for #{ sq.to_s }" }
				next
			end
	
			if $region
				$timer.start "closest_ant_region"
				ant = BaseStrategy.closest_ant_region sq, ai
				$timer.end "closest_ant_region"
			else
				ant = closest_ant_view l.coord, ai
				next if ant.collective?	
			end

			unless ant.nil?
				if ant.set_order sq, :FORAGE
					l.add_ant ant
				end
			end
		end 

		$timer.end "find_food"
	end

	def evade ai
		$logger.info "=== Evade Phase ==="
		ai.my_ants.each do |ant|
			next if ant.moved?
			ant.evading
		end
	end
	

	def ant_orders ai
		$logger.info "=== Order Phase ==="
		ai.my_ants.each do |ant|
			#next if ant.collective_leader?
			ant.handle_orders
		end
	end


	#
	# Determine which ants are being attacked
	#
	def check_attacked ai
		ai.my_ants.each do |ant|
			# WOW WHAT A STUPID BUG!
			#conflict ||= ant.check_attacked
			ant.check_attacked
		end
	end



	def turn ai, do_orders = true, do_food = true
		ant_orders ai if do_orders
		find_food ai  if do_food
		evade ai

		$logger.info "=== Default Move Phase ==="
		ai.my_ants.each do |ant|
			#$logger.info "doing default move #{ ant }"	
			#$logger.info { "#{ ant.moved? },#{ ant.collective? }, #{ ant.harvesting? }" }
			next if ant.moved?
			next if ant.collective?
			next if ant.harvesting?

			default_move ant
		end
	
		# Anything left here stays on the spot
		$logger.info "=== Stay Phase ==="
		ai.my_ants.each do |ant|
			next if ant.moved?
			ant.stay
		end

	end
end
