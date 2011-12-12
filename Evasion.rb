

module Evasion
	@@curleft = true

	@want_dir = nil
	@next_dir = nil


	def evade_init
		# Test- all ants start out with same dir
		# Works well with mazes, sucks otherwise
		#@left = false

		# Strict alternation not such a good idea, but right/left
		# runs in sync with NESW - so same dir ants always evade same way.
		#@left = @@curleft
		#@@curleft = !@@curleft

		# So let's randomize it a bit
		@left = [true,false][ rand(2) ]
	end

	def evade_reset
		@want_dir = nil
		@next_dir = nil
	end

	def evade_dir dir
		if @left
			left dir
		else 
			right dir
		end
	end

	def evade2_dir dir
		if @left
			right dir
		else 
			left dir
		end
	end


	def evading?
		!@next_dir.nil?
	end


	def evade dir
		# The direction we want to go is blocked;
		# go round the obstacle
		$logger.info { "#{ self.to_s } starting evasion" } if @want_dir.nil?
	
		done = false
		newdir = dir

		# Don't try original direction again
		(0..2).each do
			newdir = evade_dir newdir

			next if square.neighbor(newdir).hole?

			# can_pass? is supplied by the encompassing class
			if can_pass? newdir
				done = true
				break
			end
		end
	
		if done
			@want_dir = dir if @want_dir.nil?
			@next_dir = evade2_dir newdir
			order newdir
		else
			# stay is supplied by the encompassing class
			stay
		end
	end


	def evading
		unless @next_dir.nil?
			#$logger.info { "evading next_dir" }

			if can_pass? @next_dir and not square.neighbor( @next_dir).hole?

				# if the direction we're going corresponds with the
				# direction wanted, we are done.
				if @next_dir == @want_dir
					$logger.info { "#{ self } evasion complete" }
					@next_dir = nil
					@want_dir = nil
				else
					if order @next_dir
						@next_dir = evade2_dir @next_dir
					end
				end
			else 
				evade @next_dir
			end

			return true
		end

		false
	end
end


#
# pathfinder for single ant
#
class EvadePathFinder
	include Evasion

	def initialize square, dir, left
		$logger.info "EvadePathFinder init #{ square} to #{ dir }"

		@start_left = left

		@start = square
		@square = square
		@dir = dir
		@history = []

		#evade_init

		self
	end

	def find_path left
		@left = left
		@square = @start
		@history.clear
		evade_reset
		catch :done do
			evade @dir
			while evading? and has_region?
				evading

				if @square == @start
					$logger.info "Evaded back to original square!"
					break
				end
			end
		end
		str = (left )? "left" : "right"

		$logger.info { "evasion going #{ str} goes from #{ @start } to #{ @square} through #{ @history}" }
	end

	def move
		if @left.nil?
			# Go as far as you can while evading
			find_path @start_left
		else
			$logger.info { "find_path already called; not doing again" }
		end
		self
	end


	#
	# Determine which evasion direction gets you closer to the target.
	#
	# The internal state of self is set to this target
	#
	def best_direction target
		d1 = nil
		d2 = nil

		find_path true 
		if @square != @start
			target1 = @square
			d1 = $pointcache.distance target1, target
		
			history1 = @history.clone
		end

		find_path false 
		if @square != @start
			target2 = @square
			d2 = $pointcache.distance target2, target
		end

		# Select known paths over unknown paths
		do_left = false
		if d1.nil? and not d2.nil?
			$logger.info "selecting right; left is unknown"
			return false
		elsif not d1.nil? and d2.nil?
			$logger.info "selecting left; right is unknown"
			do_left = true
		elsif d1.nil? and d2.nil?
			$logger.info "No known paths"
			# Don't make any assumptions
			return nil
		end

		if do_left or d1 < d2 
			$logger.info "left is better"

			#reset internal state, it was overwritten with last search
			#find_path true 
			@left = true
			@history = history1
			@square = target1

			ret = true
		else
			$logger.info "right is better"

			ret = false
		end

		ret
	end


	def straight_path
		# Get out of a cul-de-sac first
		if @start.hole? and @history.length > 0
			$logger.info "getting out of cul-de-sac first"
			return @start.neighbor @history[0]
		end


		opposite = {
			:N => :S,
			:E => :W,
			:S => :N,
			:W => :E
		}[ @dir ]

		count = 0
		cur = @start  
		last_zero = nil 
		first_neg = false
		first_pos = false
		@history.each do |h|
			cur = cur.neighbor h

			if h == @dir
				count += 1	
			elsif h == opposite 
				count -= 1	
			end

			if count == 0
				last_zero = cur
			elsif count < 0
				break if first_pos
				first_neg = true
			else
				break if first_neg
				first_pos = true
			end
		end

		$logger.info { "last_zero #{ last_zero }" }



		unless last_zero.nil?
			dist = $pointcache.distance @start, last_zero 
			if dist == 1
				$logger.info "Not doing EVADE_GOTO over distance 1"
				return nil
			end

			# TODO: This test currently does NOTHING
			if [ :N, :S ].include? @dir and last_zero.col == @start.col
				$logger.info "last_zero column unchanged in N/S direction; ignoring"
				return nil
			elsif [ :E, :W ].include? @dir and last_zero.row == @start.row
				$logger.info "last_zero row unchanged in E/W direction; ignoring"
				return nil
			end
		end

		last_zero
	end


	def first_dir
		if @history.nil?
			nil
		else
			@history[0]
		end
	end

	# Following adapted from class Ant

	#
	# Test if folllowing square has been mapped
	#
	def has_region? 
		not @square.neighbor(@next_dir).region.nil?
	end

	def can_pass? newdir
		@square.neighbor(newdir).land?
	end

	def stay
		$logger.info "called"
		throw :done
	end

	def order dir
		@history << dir
		@square = @square.neighbor dir
		true
	end

	def square
		@square
	end
end


