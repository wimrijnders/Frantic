
class BaseStrategy

	# Default implementation does nothing
	def default_move ai
	end

	def find_food ai
		$logger.info { "getting the food" }

		# Make a list of all the current orders for foraging.
		# Keep track of the forage order sequence.
		forages = {}
		ai.my_ants.each do | ant |
			list = ant.find_orders :FORAGE	

			list.each_pair do |sq,v|
				k = sq.row.to_s + "_" + sq.col.to_s
				if forages[k].nil? or forages[k] > v
					forages[k] = v
				end
			end
		end
		$logger.info {
			str =""
			forages.each_pair do |k,v|
				str << "    #{ k }: #{v}\n"
			end

			"Found following foraging actions:\n#{ str }"
		}

		ai.food.each do |l|
			# We know the squares being foraged.
			# Only issue forages orders for squares which are not foraged yet,
			# Or which are low in the ants' lists
			sq = ai.map[ l[0] ][ l[1] ]
			k = sq.row.to_s + "_" + sq.col.to_s

			if !forages[ k ].nil? and forages[ k ] < 2
				$logger.info { "Skipping food search for #{ k }:#{ forages[k] }" }
				next
			end
			
	
			ant = closest_ant l, ai
			unless ant.nil?
				#next if ant.moved?
				next if ant.collective?
	
				ant.set_order sq, :FORAGE
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
