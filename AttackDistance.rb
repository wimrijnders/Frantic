

#
# Keep track of relative distance to the closest enemy.
#
# NOTE: The distance retained is the last move relative
#       to own ant in its current position.
#
#		Think of it as if own ant moved first, then the
#       enemy ant moves.
#
class AttackDistance

	attr_accessor :dist, :advancing, :dir


	def initialize dist, prev
		@dist = dist.clone

		@advancing = nil
		@dir = nil

		if prev
			calc_dir Distance.get prev.dist, dist

			unless too_far?
				@advancing = prev.longest_dist.abs > longest_dist.abs
			end
		end
	end
	
	def adjust dir
		@dist = @dist.adjust dir
	end

	#
	# Determine in which direction the ant went.
	#
	# If distance is more than one square, this
	# value is undefined
	def calc_dir dist
		if dist.row == 1 and dist.col == 0
			@dir = :S
		elsif dist.row == -1 and dist.col == 0
			@dir = :N
		elsif dist.row == 0 and dist.col == 1
			@dir = :E
		elsif dist.row == 0 and dist.col == -1
			@dir = :W
		elsif dist.row == 0 and dist.col == 0 
			@dir = :STAY
		else
			@dir = nil
		end

		#$logger.info "calc_dir #{ @dir }"
	end


	def longest_dist
		@dist.longest_dist
	end

	def too_far?
		@dir.nil?
	end
end


#
# List of consecutive distances between leader of collective
# and ant within attack distance.
#
# Note that the list is back to front. Last item in list
# is latest item.
#
class AttackDistanceList

	# Number of moves that need to be present in the 
	# list, before we can make an educated guess about
	# the movement of the enemy.
	TURN_LIMIT = 5

	def initialize
		@list = []
	end

	def first
		if @list.length > 1 
			@list[-1]
		else
			nil
		end
	end

	def add dist
		new = AttackDistance.new dist, first

		if first and new.too_far?

			# If there is a difference of more than 1
			# between the last and new distance, it must be 
			# a new ant. Reset the list in that case

			$logger.info "Distance changed too much. New attacker."
			clear
		end

		@list << new
	end

	#
	# Adjust last distance for movement of own ant.
	#
	def adjust dir
		first.adjust dir if first
	end

	def clear
		$logger.info "Clearing attack list."
		@list = []
	end


	def advancing
		first and first.advancing
	end

	def stay?
		return false if @list.length < TURN_LIMIT

		@list[-(TURN_LIMIT - 1)..-1].reverse.each do |d|
			return false unless d.dir == :STAY
		end

		true
	end


	def inverse? d1, d2
		( d1 == :N and d2 == :S ) or
		( d1 == :S and d2 == :N ) or
		( d1 == :E and d2 == :W ) or
		( d1 == :W and d2 == :E ) 
	end


	def twitch?
		# Twitching can not be detected from the first item in the list,
		# if current collective leader has not moved. For that reason,
		# we skip the leader and test the rest

		return false if @list.length < TURN_LIMIT + 1

		distance = @list[-2].dist.dist.abs
		@list[-(TURN_LIMIT)..-3].reverse.each do |d|
			# Twitching is only a problem if we are not getting
			# any closer; ie. the twitching is perpendicular
			return false if distance != d.dist.dist.abs
		end

		# Note: indexes start with lowest
		(-(TURN_LIMIT/2)..-2).each do |i|
			# Not staying put; every other move is the same
			# consecutive moves are not the same.
			return false if @list[i].dir == :STAY or
				@list[i].dir != @list[i-2].dir or
				not inverse? @list[i].dir, @list[i-1].dir
		end

		true
	end


	def straight_line?
		return false if @list.length < TURN_LIMIT

		# Compare rest of values with value of first
		dir = @list[-1].dir
		return false if dir == :STAY

		@list[-(TURN_LIMIT - 1)..-2].reverse.each do |d|
			return false unless d.dir == dir 
		end

		true
	end


	def to_s
		str = "attack list length: #{ @list.length }. "
		str << "Staying" if stay?
		str << "Twitching" if twitch?
		str << "Straight line" if straight_line?

		str
	end
end

