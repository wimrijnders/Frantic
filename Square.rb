
# Represent a single field of the map.
class Square
	@@ai = nil

	# Ant which sits on this square, or nil. The ant may be dead.
	attr_accessor :ant

	attr_accessor :row, :col
	attr_accessor :water, :food

	#attr_accessor :trail

	attr_accessor :region, :done_region
	
	def initialize water, food, ant, row, col, ai
		@water, @food, @ant, @row, @col = water, food, ant, row, col
		@@ai = ai if @@ai.nil?

		@moved_here = nil
		@visited = 0

		#@trail = nil
	end

	def ai
		@@ai
	end

	def self.coord_to_square coord
		@@ai.map[ coord[0] ][ coord[1] ]
	end

	def to_coord
		[ row, col ]
	end

	# This makes it easier to create functionality
	# for both ants and squares
	def square
		self
	end

	
	# Returns true if this square is not water.
	def land?; !@water; end
	# Returns true if this square is water.
	def water?; @water; end
	# Returns true if this square contains food.
	def food?; @food; end

	def to_s
		"(#{ row }, #{col})"
	end
	

	# Square is passable if it's not water,
	# and it doesn't contain alive ants
	#
	# In addition, no other friendly ant should have moved here.
	#
	def passable?

		return false if water? or food? or moved_here? 

		if ant?
			return false if @ant.enemy?

			# If there was an ant there,
			# but it is moving this turn,
			# then you can safely enter the square
			return false if @ant.pos == self
		end

		true
	end

	def moved_here?
		!@moved_here.nil?
	end

	def moved_here= val 
		@moved_here = val
	end

	def moved_here
		@moved_here
	end

	
	# Returns true if this square has an alive ant.
	def ant?; @ant and @ant.alive?; end;
	
	# Returns a square neighboring this one in given direction.
	def neighbor direction
		direction=direction.to_s.upcase.to_sym # canonical: :N, :E, :S, :W
	
		case direction
		when :N
			row, col = @@ai.normalize @row-1, @col
		when :E
			row, col = @@ai.normalize @row, @col+1
		when :S
			row, col = @@ai.normalize @row+1, @col
		when :W
			row, col = @@ai.normalize @row, @col-1
		when :STAY
			row, col = @row, @col
		else
			raise "incorrect direction '#{ direction}'"
		end
		
		return @@ai.map[row][col]
	end


	def rel relpos
		row, col = @row + relpos[0], @col + relpos[1]

		row, col = @@ai.normalize row, col

		return @@ai.map[row][col]
	end


	def visited= val
		@visited = val
	end
	def visited
		@visited
	end

	def == n
		if n.respond_to? :row
			self.row == n.row and self.col == n.col
		else
			# n is a coord array.
			self.row == n[0] and self.col == n[1] 
		end
	end

	#
	# Check if water fields are close by
	#
	def water_close? range = 2
		(-range..range).each do |row|
			(-range..range).each do |col|
				sq = rel [ row, col ]
				if sq.water?
					$logger.info { "square #{ self } has water in range #{ range}" }
					return true
				end
			end
		end

		false
	end

	#
	# Check if current square has only exit
	# 
	def hole?
		count = 0
		[ :N, :E, :S, :W ].each do |dir|
			count += 1 if neighbor(dir).water?
		end

		count == 3
	end
end

