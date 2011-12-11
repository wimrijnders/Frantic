
class Move

	attr_accessor :pos, :dir


	def initialize pos, prev = nil
		@pos = pos.clone

		@dir = nil
		if prev
			dist = Distance.get prev, pos
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

		#$logger.info "calc_dir #{ @dir }"
	end


	def too_far?
		@dir.nil?
	end
end


class MoveHistory

	# Number of moves that need to be present in the 
	# list, before we can make an educated guess about
	# the movement of the enemy.
	TURN_LIMIT = 4

	def initialize
		@list = []
	end

	def first
		if @list.length > 0 
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

	def length
		@list.length 
	end

	def clear
		$logger.info "Clearing attack list."
		@list = []
	end


	def advancing? pos
		# special case for straight-liners; sometimes one can be seen
		# as advancing when directly in front of leader
		if straight_line?
			if first and @list[-2]
				dist1 = Distance.get pos, first.pos
				dist2 = Distance.get pos, @list[-2].pos
			end

			return dist1.longest_dist.abs < dist2.longest_dist.abs
		end

		if first and @list[-2]
			dist1 = Distance.get pos, first.pos
			dist2 = Distance.get pos, @list[-2].pos

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
		#pos = @list.reverse.collect { |d| d.pos }
		#dir = @list.reverse.collect { |d| d.dir }

		str = "History list length: #{ @list.length }. "
		#str << pos.join( "," )
		#str << dir.join( ":" )
		str << "Staying" if stay?
		str << "Twitching" if twitch?
		str << "Straight line" if straight_line?

		str
	end

	def dir 
		@list[-1].dir
	end


	def can_guess_dir?
		straight_line? or twitch?  or stay?
	end

	def guess_dir square = nil
		if straight_line?
			dir
		elsif twitch?
			reverse dir
		elsif stay?
			:STAY
		elsif dir.nil?
			# If specified, assume worst move for us (ie advancing)
			unless square.nil? or first.nil?
				Distance.get( first.pos, square).dir	
			else
				# Assume ant stays still and hope, really hope for the best
				:STAY 
			end
		else
			# ditto
			unless square.nil? or first.nil?
				Distance.get( first.pos, square).dir	
			else
				# Assume ant continues previous movement and hope for the best
				dir	
			end
		end
	end
end


class Trail

	def initialize
		@dirs = {}
	end

	def add dir
		if @dirs[ dir ]
			@dirs[ dir] += 1
		else
			@dirs[ dir] = 1
		end
	end

	#
	# Select a direction to move in, based on trail frequency
	#
	def get_dir
		$logger.info "Called get_dir."
		total = 0
		@dirs.each_pair do |dir, count |
			total += count
		end

		select = rand( total ) + 1
		$logger.info "Total #{ total }, select #{ select}."

		total = 0
		@dirs.each_pair do |dir, count |
			total += count
			return dir if total >= select
		end

		nil
	end


	#
	# Top-level strategy.
	#
	# If present, follow trail.
	#
	def self.follow_trail ant
		if ant.square.trail
			dir = ant.square.trail.get_dir
			if dir
				$logger.info "#{ ant.to_s } following trail to #{ dir }."
				ant.clear_order :HARVEST
				#ant.evade_reset
				ant.move dir
			end
			true
		else
			false
		end
	end
end


class MoveFriendly
	attr_accessor :dir, :square

	def initialize  dir, square
		@dir, @square = dir, square
	end
end

class MoveHistoryFriendly
	def initialize
		@list = []
	end

	def add dir, square

		# close off loops
		@list.reverse.each do |l|
			if square == l.square
				$logger.info "Found loop in trail at square #{ square }; closing off."
				index = @list.index l
				@list = @list[0..index]
				return
			end
		end

		item =  MoveFriendly.new dir, square 
		@list << item 
	end

	def set_trail firstsq 
		return if @list.length == 0

		sq = firstsq

		@list.reverse.each do |l|
			dir = l.dir
			d = reverse dir
			sq = sq.neighbor d

			# No trails on top of our hill!
			break if $ai.hills.my_hill?  [ sq.row, sq.col ]

			unless sq.trail
				sq.trail = Trail.new
			end
			sq.trail.add dir
		end

		$logger.info "Done laying trail from #{ sq.to_s } to #{ firstsq.to_s}; length #{ @list.length }"

		@list = []
	end
end
	
