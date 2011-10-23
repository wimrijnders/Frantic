
class BaseStrategy

	# Default implementation does nothing
	def default_move ai
	end

	def find_food ai
		$logger.info { "getting the food" }
		ai.food.each do |l|
	
			ant = closest_ant l, ai
			unless ant.nil?
				#next if ant.moved?
				next if ant.collective?
	
				ant.set_order ai.map[ l[0] ][ l[1] ], :FORAGE
			end
		end 
		$logger.info { "done getting the food" }
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
