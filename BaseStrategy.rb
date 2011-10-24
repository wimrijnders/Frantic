
class BaseStrategy

	# Default implementation does nothing
	def default_move ai
	end

	def self.closest_ant_region sq, ai
		sq_ants = []
		ai.my_ants.each do |ant|
			next if ant.moved?
			next if ant.collective?

			sq_ants << ant.square
		end

		# Note that the search is actually back to front, from food
		# to ants. The distance of course is the same
		path = Pathinfo.shortest_path sq, sq_ants

		return nil unless path

		from_r = sq.region

		# Now, determine which ants are in the given region
		antlist = []
		ai.my_ants.each do |ant|
			# This is the same as loop above
			# TODO: consolidate this
			next if ant.moved?
			next if ant.collective?

			if path.length == 0
				antlist << ant if from_r == ant.square.region
			else
				antlist << ant if path[-1] == ant.square.region
			end
		end

		# Due to the tests on moved and collective, it is possible that
		# the list is empty
		return nil if antlist.length == 0

		# Of these ants, determine the closest
		best_ant = nil
		best_dist = -1
		antlist.each do |ant|
			# Path is passed as parameter, so find_path() is not called 
			pathinfo = Pathinfo.new sq, ant.square, path

			if best_ant.nil? or pathinfo.dist < best_dist
				best_ant = ant
				best_dist = pathinfo.dist
			end	
		end
		$logger.info { "best ant: #{ best_ant}, dist: #{ best_dist}" }

		best_ant
	end


	def find_food ai
		$timer.start "find_food"
		$logger.info { "getting the food" }


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
				ant = closest_ant l.coord, ai
				next if ant.collective?	
			end

			unless ant.nil?
				if ant.set_order sq, :FORAGE
					l.add_ant ant
				end
			end
		end 
		$logger.info { "done getting the food" }
		$timer.end "find_food"
	end

	def evade ai
		ai.my_ants.each do |ant|
			next if ant.moved?
			ant.evading
		end
	end
	

	def ant_orders ai
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

		ai.my_ants.each do |ant|
			next if ant.moved?
			next if ant.collective?
			next if ant.harvesting?
	
			default_move ant
		end
	
		# Anything left here stays on the spot
		ai.my_ants.each do |ant|
			next if ant.moved?
			ant.stay
		end

	end
end
