
# Represents a single ant.
class Ant

	# Owner of this ant. If it's 0, it's your ant.
	attr_accessor :owner
	# Square this ant sits on.
	attr_accessor :square, :moved_to
	
	attr_accessor :alive, :ai
	attr_accessor :collective

	include Evasion
	
	def initialize alive, owner, square, ai
		@alive, @owner, @square, @ai = alive, owner, square, ai

		@moved= false

		@attack_distance = nil
		@orders = []

		evade_init
	end


	#
	# Perform some cleanup stuff when an ant dies
	#
	def die
		@collective.remove self	if collective?
	end
	
	def alive?; @alive; end
	def dead?; !@alive; end
	def mine?; owner==0; end
	def enemy?; owner!=0; end
	def row; @square.row; end
	def col; @square.col; end

	# Order this ant to go in given direction.
	# Equivalent to ai.order ant, direction.

	def order direction
		@square.neighbor( direction ).moved_here = self
		@moved= true
		@moved_to= direction

		@ai.order self, direction
	end

	def square= sq
		@square = sq
	end

	def stay
		$logger.info "Ant stays at #{ @square.to_s }."
		@square.moved_here = self
		@moved = true
		@moved_to = nil
	end


	def moved= val
		@moved = val
	end

	def moved?
		@moved
	end

	def can_pass? newdir
		square.neighbor(newdir).passable?
	end

	def move dir
		str = "move from #{ square.to_s } to #{ dir } - "

		if can_pass? dir
			str +=  "passable"
			order dir
		else
			evade dir
if false
			str += "Not passable"
			if square.neighbor( dir ).water?
				evade dir
			else
				unless attacked?
					# Just pick any direction we can move to
					directions = [:N, :E, :S, :W ]
					directions.each do |d|
						sq = square.neighbor( d )
						if sq.passable?
							order d
							$logger.info str + "; picked #{ d }"
							return
						end
					end
				end

				# no directions left or under attack
				stay
			end
end
		end
		$logger.info str
	end

	#
	# Move ant to specified direction vector
	#
	def move_dir d
		move d.dir( @square)
	end

	#
	# Move ant in the direction of the specified square
	# 
	def move_to to
		move_dir Distance.new( @square, to)
	end

	def retreat
		return if attack_distance.nil?

		$logger.info "Retreat."
		move_dir attack_distance.invert
	end


	def check_attacked
		d = closest_enemy self, self.ai.enemy_ants 
		unless d.nil?
			if d.in_view? and d.clear_view @square
				$logger.info "ant #{ @square.to_s } attacked!"

				@attack_distance = d
				return true
			end
		end

		@attack_distance = nil
		false
	end

	def attacked?
		!@attack_distance.nil?
	end

	def attack_distance
		@attack_distance
	end

	def set_order square, what, offset = nil
		n = Order.new(square, what, offset)

		@orders.each do |o|
			# order already present
			return if o == n
		end

		# ASSEMBLE overrides the rest of the orders
		if what == :ASSEMBLE
			@orders = []
		end

		@orders << n

		# Nearest orders first
		@orders.sort! do |a,b|
			adist = Distance.new( self.pos, a.square)
			bdist = Distance.new( self.pos, b.square)

			adist.dist <=> bdist.dist
		end
	end

	def clear_orders
		@orders = []

		#evade_reset
	end

	def orders?
		@orders.size > 0
	end


	def order_distance
		return nil unless orders?

		Distance.new pos, @orders[0].square
	end

	def remove_target_from_order t
		if orders?
			p = nil
			@orders.each do |o|
				if o.target? t
					p = o 
					$logger.info("Found p")
					break
				end
			end

			@orders.delete p unless p.nil?
		end
	end

	def handle_orders
		return false if moved?

		prev_order = (orders?) ? @orders[0].square: nil

		while orders?
			if self.square == @orders[0].square
				# Done with this order, reached the target
				$logger.info "Reached the target at #{ @orders[0].square.row }, #{ @orders[0].square.col }"

				@orders = @orders[1..-1]
				next
			end

			if @orders[0].order == :ASSEMBLE
				if !collective
					@orders = @orders[1..-1]
					next
				end
			end

			# Check if in-range when visible for food
			if @orders[0].order == :FORAGE
				sq = @orders[0].square
				closest = closest_ant [ sq.row, sq.col], @ai
				unless closest.nil?
					d = Distance.new closest, sq

					if d.in_view? and !@ai.map[ sq.row ][sq.col].food?
						# food is already gone. Skip order
						@orders = @orders[1..-1]
						next
					end
				end
			end

			break
		end

		return false if !orders?

		if evading?
			if prev_order != @orders[0].square
				# order changed; reset evasion
				evade_reset
			else
				# Handle evasion elsewhere
				return false
			end
		end

		if @orders[0].order == :ASSEMBLE
			$logger.info "Moving to #{ @orders[0].square.to_s }"
		end
		move_to @orders[0].square

		true
	end

	#
	# Return actual position of ant, taking
	# movement into account.
	#
	# In effect, this is the position of the ant
	# in the next turn.
	#
	def pos
		if moved? and not moved_to.nil?
			square.neighbor( moved_to )
		else
			square
		end
	end

	def collective?
		not @collective.nil? # and @collective.size > 0
	end

	def collective_leader?
		collective? and @collective.leader? self
	end

	def add_collective a

		if @collective.nil?
			make_collective
		end
		return if @collective.filled?

		@collective.add a
		a.set_collective @collective

		@collective.rally a,
	end

	def set_collective c 
		@collective = c
	end

	def make_collective 
		@collective = Collective2.new 
		@collective.add self
		clear_orders
	end

	def move_collective 
		@collective.move
	end
end

