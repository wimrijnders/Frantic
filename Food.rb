
class Food
	COUNTER_LIMIT = 10

	attr_accessor :coord, :active

	def initialize coord
		@coord = coord
		@active = true
		@ants = []
		@counter = $ai.turn_number
	end

	def == coord
		@coord[0] == coord[0] and @coord[1] == coord[1]
	end

	def row
		@coord[0]
	end

	def col
		@coord[1]
	end

	def square 
		$ai.map[ @coord[0] ][ @coord[1] ]
	end

	def add_ant ant
		unless @ants.include? ant
			@ants << ant
			$logger.info { "Added ant #{ ant } to food." }
		else
			$logger.info { "Ant #{ ant } already present in food." }
		end
	end

	def remove_ant ant
		index = @ants.index ant

		if index
			@ants.delete ant
			$logger.info { "Removed ant #{ ant } from food." }
		#else
		#	$logger.info { "Ant #{ ant } not present in food." }
		end
	end


	def clear_orders
		@ants.each do |ant|
			ant.remove_target_from_order ant.ai.map[ row ][ col]
		end
	end

	def reset
		@counter = $ai.turn_number + COUNTER_LIMIT
	end

	#
	#
	def should_forage?
		if @counter <= $ai.turn_number
			$logger.info "Food #{ coord } counter ran out, signal to be found."
			return true
		else
			@counter -= 1
			return false
		end
	end

end


class FoodList
	@ai = nil

	def initialize ai
		@ai = ai unless @ai
		@list = []
	end

	def start_turn
		@list.each { |f| f.active = false }
	end

	def add coord
		# Check if already present

		index = @list.index coord

		if index
			$logger.info { "Food at #{ coord } already present" }
			@list[index].active = true
		else
			$logger.info { "New food at #{ coord }" }
			@list << Food.new( coord )
			Region.add_searches @ai.map[ coord[0]][ coord[1] ], @ai.my_ants, true
		end
	end

	def remove coord
		index = @list.index coord
		if index
			if @list[index].active
				$logger.info { "Food for deletion at #{ coord } still active!" }
			end

			# Tell all ants not to search for this food
			@list[index].clear_orders

			@list.delete_at index
		else
			$logger.info { "Food for deletion at #{ coord } not present!" }
		end
	end

	def each
		@list.each {|l| yield l if l.active }
	end

	def remove_ant ant, coord = nil
		if coord
			index = @list.index coord
			if index
				@list[index].remove_ant ant
			else
				$logger.info { "Food at #{ coord } not present" }
			end
		else
			# Remove ant from all coords
			@list.each {|l| l.remove_ant ant }
		end
	end

	def active? coord
		@list.each {|l| 
			if l.coord == coord
				return l.active
			end
		}

		# Food not present in list
		nil
	end
end

