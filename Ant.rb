
# Represents a single ant.
class Ant
	# Owner of this ant. If it's 0, it's your ant.
	attr_accessor :owner

	# Square this ant sits on.
	attr_accessor :square

	attr_accessor :alive, :ai

	def initialize alive, owner, square, ai
		@alive, @owner, @square, @ai = alive, owner, square, ai
	end

	def alive?; @alive; end
	def dead?; !@alive; end
	def mine?; owner==0; end
	def enemy?; owner!=0; end
	def row; @square.row; end
	def col; @square.col; end

	def square= sq
		@square = sq
	end

	def pos
		square
	end

	def to_s
		"ant" + square.to_s
	end
end


class EnemyAnt < Ant

	def initialize owner, square, ai
		super  true, owner, square, ai

		@state = nil
	end

	def state
		@state
	end

	def state?
		!@state.nil?
	end

	def transfer_state ant
		@state = ant.state

		@state.add ant.square
	end

	def init_state
		@state = MoveHistory.new

		@state.add @square
	end

	def to_s
		super + "; " +  @state.to_s
	end

	def advancing? pos
		@state.advancing? pos
	end

	def straight_line? 
		@state.straight_line?
	end

	def twitch?
		@state.twitch?
	end


	def dir
		@state.dir
	end 
	
end


class MyAnt < Ant
	@@default_index = 0


	# Square this ant sits on.
	attr_accessor :moved_to, 
		:abspos # absolute position relative to leader, if part of collective
	
	attr_accessor :collective, :friends, :enemies

	#attr_accessor :trail

	include Evasion
	include Orders
	
	def initialize square, ai
		super  true, 0, square, ai

		@moved= false

		@attack_distance = nil
		@enemies = [] 

		@default = [ :N, :E, :S, :W ][ @@default_index ]
		@@default_index = ( @@default_index + 1 ) % 4

		evade_init
		orders_init

		#@trail = MoveHistoryFriendly.new 
	end

	def default
		best = nil;
		best_dir = nil;
		# Select least visited direction
		# Randomize a bit, otherwise it will persevere in a given direction
		[ :N, :E, :S, :W, :N,:E, :S, :W ][ rand(4).to_i, 4].each do |dir|
			visited = @square.neighbor( dir ).visited

			if best.nil? or best > visited
				best = visited
				best_dir = dir
			end
		end
	
		if best.nil?
			# Prob never called; never mind
			@default
		else
			best_dir
		end	
	end

	#
	# Perform some cleanup stuff when an ant dies
	#
	def die
		@collective.remove self	if collective?
		@ai.harvesters.remove self	if @ai.harvesters
	end
	
	# Order this ant to go in given direction.
	# Equivalent to ai.order ant, direction.

	def order direction
		# Following needed because duplicate orders
		# are filed as errors on the site.
		# TODO: Fix this so that no duplicate errors occur
		if moved?
			$logger.info "ERROR - duplicate move detected"
			# Original is retained
			return
		end

		@square.neighbor( direction ).moved_here = self
		@moved= true
		@moved_to= direction

		#@trail.add direction, @square

		@ai.order self, direction
	end

	def stay
		$logger.info { "Ant stays at #{ @square.to_s }." }
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
		end
		$logger.info { str }
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
		@attack_distance = nil
		return false unless @enemies[0]

		d = Distance.new self, @enemies[0]

		unless d.nil?
			if d.in_view? and d.clear_view @square
				$logger.info { "ant #{ @square.to_s } attacked by #{ @enemies[0] }!" }

				@attack_distance = d
				return true
			end
		end

		false
	end

	def attacked?
		!@attack_distance.nil?
	end

	def attack_distance
		@attack_distance
	end


	#
	# Return actual position of ant, taking
	# movement into account.
	#
	# In effect, this is the position of the ant
	# in the next turn.
	#
	def pos
		if not moved_to.nil? and moved?
			square.neighbor( moved_to )
		else
			square
		end
	end


	#
	# create a sorted list from the given ant list.
	#
	# Sorted ascending by closest distance to current ant
	#
	def closest_list list
		closest = list.sort do |a,b|
			adist = Distance.new( pos, a.pos)
			bdist = Distance.new( pos, b.pos)

			adist.dist <=> bdist.dist
		end
		closest
	end


	def make_friends
		if @friends.nil?
			@friends = closest_list(ai.my_ants)	

			@friends.delete self
		end
	end


	#
	# Return all friendly ants within the specified distance
	#
	def neighbor_friends dist
		make_friends

		neighbors = []
		@friends.each do |a|
			adist = Distance.new( pos, a.pos)
			break if adist.dist > dist

			neighbors << a
		end

		neighbors
	end

	def closest_friend_dist
		make_friends

		return nil if @friends[0].nil?

		Distance.new self, @friends[0]
	end

	def closest_enemy_dist
		return nil if @enemies[0].nil?

		Distance.new self, @enemies[0]
	end



	def neighbor_enemies dist
		neighbors = []
		@enemies.each do |a|
			adist = Distance.new( pos, a.pos)
			break if adist.dist > dist

			neighbors << a
		end

		neighbors
	end


	def enemies_in_view
		neighbors = []
		@enemies.each do |a|
			adist = Distance.new( pos, a.pos)
			break unless adist.in_view?

			neighbors << a
		end

		neighbors
	end




	#
	# Reset variables at the start of a turn
	# TODO: Why does this screw up movement?
	#
	def reset_turn
		moved = false
		moved_to = nil
	end


	def collective?
		not @collective.nil? # and @collective.size > 0
	end

	def collective_leader?
		collective? and @collective.leader? self
	end

	def add_collective a, size = nil
		return if a.collective?

		if @collective.nil?
			make_collective size
		end
		return if @collective.assembled? false

		@collective.add_recruit a
	end

	def collective_assembled?
		return false if @collective.nil?

		@collective.assembled? false
	end

	def set_collective c 
		@collective = c
	end

	def make_collective size = nil
		if !size.nil? and size >= 2
			@collective = Collective3.new 
		else
			@collective = Collective2.new 
		end
		@collective.add self
		clear_orders
	end

	def move_collective 
		@collective.move #unless @collective.nil?
	end


	def add_enemy e
		# Only add if within reasonable distance
		dist = Distance.new self, e

		if dist.dist < 20
			@enemies << e
		end
	end


	def sort_enemies
		@enemies = closest_list @enemies
	end


	def neighbor_attack
		# Check for direct friendly neighbours 
		done = false
		has_neighbour = false
		[ :N, :E, :S, :W ].each do |dir|
			n = square.neighbor( dir ).ant
			next if n.nil?
	
			has_neighbour = true
	
			if n.mine?
				if n.moved? and not n.moved_to.nil?
					# if neighbour moved, attempt the same move
					$logger.info "neighbour moved."
					move n.moved_to
					done = true
					break
				end
			end
		end
		return if done
	
	
		if has_neighbour
			# Neighbours didn´t move, perform attack yourself
			$logger.info "Attack."
	
			move attack_distance.attack_dir
			return 
		end
	
		# Find a close neighbour and move to him
		d = closest_friend_dist
		$logger.info { "closest friend: #{ d.to_s }" }
		unless d.nil?
			dist = d.dist
			if dist == 1 
				$logger.info "next to friend."
				# already next to other ant
				stay
			elsif dist < 20
				$logger.info "Moving to friend."
				move_dir d
			end
			return 
		end
	
		# Otherwise, just run away
		retreat
		return 
	end


	def neighbor_help
		order_dist = order_distance
	
		# Find an attacked neighbour and move in to help
		ai.my_ants.each do |l|
			next unless l.attacked?
	
			d = Distance.new self, l.pos	
	
			# Only help out if current ant has no order,
			# or ant in distress is nearer
			if order_dist and order_dist.dist < d.dist
				# Skip helping friend, we have other things to do
				next
			end
	
			if d.dist == 1 
				$logger.info "Moving in - next to friend." 
				stay
			elsif d.in_view?
				$logger.info "Moving in to help attacked buddy."
				move_to l.pos
			end
		end
	end


	def handle_conflict
		return if moved?
	
		# If we can complete the order before being in conflict, 
		# the order will take precedence.
		return if check_orders


		if ai.kamikaze?
			# Pick the nearest enemy and go for it
			$logger.info "Banzai!"
			d = closest_enemy_dist
			unless d.nil?
				move d.attack_dir 
				return
			end
		end
	
		if attacked?
			#retreat and return if ai.defensive?

			if ai.aggresive? and enemies.length == 1
				move attack_distance.attack_dir
				return 
			end
	
			$logger.info "Conflict!"

			#d = closest_enemy_dist
			#retreat if !d.nil? and  d.in_peril?

			neighbor_attack
		else
			neighbor_help
		end
	end

	def harvesting?
		!find_order( :HARVEST).nil?
	end
end

