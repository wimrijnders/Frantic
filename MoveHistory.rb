

class Move

	attr_accessor :pos, :dir


	def initialize pos, prev = nil
		@pos = pos.clone

		@dir = nil

		if prev
			dist = Distance.new prev, pos
			calc_dir dist
		end
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

		$logger.info "calc_dir #{ @dir }"
	end


	def too_far?
		@dir.nil?
	end
end


class MoveHistory

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

	def add pos
		if first
			new = Move.new pos, first.pos
		else
			new = Move.new pos
		end

		# TODO: This still needed?
		if first and new.too_far?

			# If there is a difference of more than 1
			# between the last and new distance, it must be 
			# a new ant. Reset the list in that case

			$logger.info "Distance changed too much. New attacker."
			clear
		end

		@list << new
	end


	def clear
		$logger.info "Clearing attack list."
		@list = []
	end


	def advancing? pos
		# special case for straigh-liners; sometimes one can be seen
		# as advincing when directly in front of leader
		if straight_line?
			if first and @list[-2]
				dist1 = Distance.new pos, first.pos
				dist2 = Distance.new pos, @list[-2].pos
			end

			return dist1.longest_dist.abs < dist2.longest_dist.abs
		end

		if first and @list[-2]
			dist1 = Distance.new pos, first.pos
			dist2 = Distance.new pos, @list[-2].pos

			return dist1.dist.abs < dist2.dist.abs
		end


		false
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
		return false if @list.length < TURN_LIMIT

		pos = @list[-1].pos

		# Note: indexes start with lowest
		(-( (TURN_LIMIT-1)/2 )..-1).each do |i|

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
		str = "History list length: #{ @list.length }. "
		str << "Staying" if stay?
		str << "Twitching" if twitch?
		str << "Straight line" if straight_line?

		str
	end

	def dir 
		@list[-1].dir
	end
end

