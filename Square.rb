
# Represent a single field of the map.
class Square
	# Ant which sits on this square, or nil. The ant may be dead.
	attr_accessor :ant
	# Which row this square belongs to.
	attr_accessor :row
	# Which column this square belongs to.
	attr_accessor :col
	
	attr_accessor :water, :food, :ai
	attr_accessor :trail, :region
	
	def initialize water, food, ant, row, col, ai
		@water, @food, @ant, @row, @col, @ai = water, food, ant, row, col, ai

		@moved_here = nil
		@visited = 0

		@trail = nil
	end
	
	# Returns true if this square is not water.
	def land?; !@water; end
	# Returns true if this square is water.
	def water?; @water; end
	# Returns true if this square contains food.
	def food?; @food; end

	def to_s
		"( #{ row }, #{col} )"
	end
	

	# Square is passable if it's not water,
	# it doesn't contain alive ants and it doesn't contain food.
	#
	# In addition, no other friendly ant should have moved here.
	def passable?

		return false if water? or food?  or moved_here? 

		#$logger.info "passable #{ self.to_s }: #{ ant? }, #{ @ant.pos.to_s if ant? }"
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
			row, col = @ai.normalize @row-1, @col
		when :E
			row, col = @ai.normalize @row, @col+1
		when :S
			row, col = @ai.normalize @row+1, @col
		when :W
			row, col = @ai.normalize @row, @col-1
		else
			raise 'incorrect direction'
		end
		
		return @ai.map[row][col]
	end

	def rel relpos
		row, col = @row + relpos[0], @col + relpos[1]

		row, col = @ai.normalize row, col

		return @ai.map[row][col]
	end


	def visited= val
		@visited = val
	end
	def visited
		@visited
	end

	def == n
		self.row == n.row and self.col == n.col
	end
end

