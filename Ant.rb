
# Represents a single ant.
class Ant < AntObject
	@@id_counter = 0

	# Owner of this ant. If it's 0, it's your ant.
	attr_accessor :owner

	# Square this ant sits on.
	attr_accessor :square

	attr_accessor :alive, :ai

	def initialize alive, owner, square, ai
		super

		@alive, @owner, @square, @ai = alive, owner, square, ai

		@id = @@id_counter
		@@id_counter += 1
	end

	def id; @id; end
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
		"ant_#{id}#{ square.to_s }"
	end
end


class EnemyAnt < Ant

	attr_accessor :state

	def initialize owner, square, ai, alive = true
		super  alive, owner, square, ai

		@state = nil
	end

	def state?
		!@state.nil?
	end

	def transfer_state ant
		@state = ant.state

		@state.add self.square
	end

	def init_state
		@state = MoveHistory.new

		@state.add @square
	end

	def to_s
		"enemy_#{id}#{ square }; " +  @state.to_s
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

	def stay?
		@state.stay?
	end


	def dir
		@state.dir
	end 


	def guess_next_pos sq_in = nil
		dir = @state.guess_dir sq_in

		if dir == :STAY
			square
		else
			square.neighbor dir
		end
	end	
end


class MyAnt < Ant
	@@default_index = 0


	# Square this ant sits on.
	attr_accessor :moved_to, :prev_move, 
		:abspos,    # absolute position relative to leader, if part of collective
		:been_there	# Regions through which this ant has passed
	
	attr_accessor :collective, :enemies
	attr_writer   :friends

	#attr_accessor :trail

	include Evasion
	include Orders
	
	def initialize square, ai
		super  true, 0, square, ai

		@moved= false

		@attack_distance = nil
		@enemies = [] 
		@friends = [] 

		@default_i = @@default_index
		@default = [ :N, :E, :S, :W ][ @@default_index ]
		@@default_index = ( @@default_index + 1 ) % 4
		@next_move = nil
		@prev_move = nil

		#@next_default_dir = 0

		evade_init
		orders_init

		#@trail = MoveHistoryFriendly.new 

		@been_there = []
	end


	def default
		# Don't stay as default move; ant might need to get out of the
		# way later on. In any case, ant is put on stay in turn_end
		#return :STAY if stuck?
		return nil if stuck?

		target = BorderPatrolFiber.request_target self.pos, self.been_there
		unless target.nil?
			#if @ai.aggresive?
			#	set_order target, :DEFEND
			#	return nil 
			#else
				if set_order target, :GOTO
					# Attempt to move in the right direction
					item = $pointcache.get self.square, target 
					return item[2] unless item.nil?
				end
			#end
		end


		# Attempts to use intelligent default movement here all have adverse effect
		# on movement downstream (loads of twitching). Best to not be clever about movement
		# here

		best = true
		best_dir = @default
	
		if best.nil?
			#@default
			$logger.info "stuck in default move"
			#:STAY 
			nil
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
		@ai.food.remove_ant self
	end
	
	# Order this ant to go in given direction.
	# Equivalent to ai.order ant, direction.

	def order direction
		# Following needed because duplicate orders
		# are filed as errors on the site.
		# Looks to be going fine; but it's a good safeguard
		if moved?
			$logger.info "ERROR - duplicate move detected"
			# Original is retained
			return false
		end

		if @ai.order self, direction
			# order accepted - change state of ant now.
			next_sq = @square.neighbor( direction )
			next_sq.moved_here = self
			@moved= true

			@moved_to= direction
			@prev_order = @orders[0]

			next_region = next_sq.region
			unless @been_there.include? next_region
				@been_there << next_region
			end


			#@trail.add direction, @square
			true
		else
			$logger.info { "#{ self } move #{ direction } blocked on output" }
			false
		end
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

	def can_pass? newdir, do_cur_ant = true
		square.neighbor(newdir).passable? do_cur_ant
	end


	# Generate all possible movements of this ant 
	def all_moves harmless
		# NOTE: harmless test disabled
		harmless = false

		moves = {} 

		if moved? or next_to_enemy?
			moves[ :STAY ] = pos
			return moves
		end

		lam = lambda do |dir| 
			# Test movement of collective
			if can_pass? dir, false
				moves[ dir ] = square.neighbor dir
			end
		end

		# Note that we don't bother with orientation so close to conflict	

		if harmless
			$logger.info { "#{ self } attackers harmless; staying is not an option" }
		else
			moves[ :STAY ] = square
		end
		lam.call :N
		lam.call :E
		lam.call :S
		lam.call :W

		if moves.empty?
			$logger.info "We are stuck, apparently; staying anyway."
			moves[ :STAY ] = square
		end

		$logger.info { "possible moves: #{ moves }" }

		moves
	end


	#
	# Check if ant can not move at all
	#
	def stuck?
		[ :N, :E, :S, :W ].each do |dir|
			return false if can_pass? dir
		end

		true
	end


	#
	# Return true if the requested direction could be taken, false otherwise
	#
	def move dir, target = nil, always_move = true

		strf = "#{ self } to #{ dir } => #{ target } - %s"
		$logger.info { strf % [ 'entered' ] }

		next_sq = square.neighbor(dir)

		$logger.info {
			"dir #{ dir }, next_sq: #{ next_sq }, " +
			"can_pass: #{ can_pass? dir }; hole: #{ next_sq.hole?}"
		}

		if dir == :STAY
			stay
			$logger.info { strf % [ 'staying' ] }
			return true
		# If next square is a hole and not our target, we dont want to go there
		elsif can_pass? dir and ( ( not target.nil? and next_sq == target ) or  not next_sq.hole? )
			$logger.info { strf % [ 'passable' ] }
			order dir
			return true
		end

		unless always_move
			$logger.info { strf % [ 'move failed' ] }
			return false
		else
			$logger.info { strf % [ 'trying evasion' ] }
		end


		str = ""

		if ( next_sq.ant? and not next_sq.ant.moved? ) or next_sq.moved_here?

			# if you got here, you know where you are going.
			# Don't initiate an evasion, either move to empty square or sit it out.
			tmp = square.passable_directions

			# Don't go back if you can help it
			tmp -= [ reverse( dir ) ]
			if tmp.empty?
				stay
			else
				order tmp[0]
			end
		else

			# Only use pathfinder on water squares
			unless next_sq.water?
				# Do regular evasion
				evade dir
				#stay	- bad idea
				return false
			end

			path_finder = EvadePathFinder.new square, dir, @left

			do_it = true
			unless target.nil?
				best = path_finder.best_direction target
				if best.nil?
					str = "Have no path"
					do_it = false
				else
					@left = best
				end
			end

			if do_it
				evade_target = path_finder.move.straight_path
	
				if evade_target.nil?
					# Follow the regular evasion
					evade dir
				else
	
					# Take a shortcut to a point on the evasion path
					if set_order evade_target, :EVADE_GOTO, nil, true
	
						# Take the first step, since we are already committed
						# to moving.
						dir = path_finder.first_dir
						if not dir.nil? and square.neighbor(dir).passable?
							order dir
						end
						str = "taking shortcut through #{ dir }"
					else
						# Fall back to regular evasion
						evade dir
					end
				end
			end
		end

		$logger.info { strf % [ str ] }
		return false
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
		d = Distance.get( @square, to)
		move d.dir( @square), to
	end

	def retreat
		return if attack_distance.nil?

		$logger.info "Retreat."
		move_dir attack_distance.invert
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
	# Friendly ants
	# 

	def make_friends
		if @friends.nil?
			$logger.info "Sorting friends."
			@friends = ai.neighbor_ants self.square
			#@friends = $region.get_neighbors_sorted self, ai.my_ants

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
			break if a[1] > dist

			neighbors << a[0]
		end

		neighbors
	end

	def closest_friend
		make_friends

		@friends[0]
	end

	def friends
		make_friends

		@friends
	end

	# 
	# Enemy ants
	#

	def closest_enemy
		return nil if  @enemies[0].nil?

		@enemies[0][0]
	end


	def neighbor_enemies? dist
		# enemies list is sorted, just check the first
		return false if @enemies.nil? or @enemies.length == 0

		@enemies[0][1] < dist
	end


	def enemies_in_view
		# all enemies are in view

		neighbors = []
		@enemies.each do |a|
			#adist = Distance.get( pos, a[0].pos)
			#break unless adist.in_view?

			neighbors << a[0]
		end

		neighbors
	end

if false
	def add_enemies enemies
		@enemies = $region.get_neighbors_sorted self, enemies
	end
end


	def check_attacked
		@attack_distance = nil

		enemy = closest_enemy 
		return false if enemy.nil? 

		#
		# Note: we use direct distance here, even if there are paths.
		#       This is because view distances work with direct distances 
		d = Distance.get self, enemy

		unless d.nil?
			#if d.in_view? and Distance.direct_path?( self.square, enemy )
			if d.in_view? and $pointcache.has_direct_path( self.square, enemy )
				$logger.info { "ant #{ @square.to_s } attacked by #{ enemy }!" }

				@attack_distance = d
				return true
			end
		end

		false
	end



	#
	# Reset variables at the start of a turn
	# TODO: Why does this screw up movement?
	#
	def reset_turn
		#$logger.info "Entered"

		#moved = false
		#moved_to = nil
		@next_move = nil
		@enemies = []
		@friends = nil  #[]
	end

	#
	# Determine and return next move to perform. 
	# If no next move, value is 'true'
	# If move should not be handled through handle_orders, value is 'false'
	#
	def next_move
		if @next_move.nil?
			@next_move = determine_next_move
		end

		@next_move
	end

	def clear_next_move
		@next_move = nil
		evade_reset
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

	def collective_follower?
		collective? and collective_assembled? and not collective_leader?
	end

	def set_collective c 
		@collective = c
	end

	def make_collective size = nil
		#if !size.nil? and size >= 2
		#	@collective = Collective3.new 
		#else
			@collective = Collective2.new 
		#end
		@collective.add self
		clear_orders
	end

	def move_collective 
		@collective.move #unless @collective.nil?
	end


	def neighbor_attack
		$logger.info "entered"

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
		return true if done
	
	
		if has_neighbour
			# Neighbours didn´t move, perform attack yourself
			$logger.info "Attack."
	
			move attack_distance.attack_dir
			return true
		end
	
		# Find a close neighbour and move to him
		friend = closest_friend
		$logger.info { "Closest friend : #{ friend }" }
		unless friend.nil?
			dist = friend[1]
			if dist == 1 
				$logger.info "Next to friend."
				# already next to other ant
				stay
			elsif dist < 20
				$logger.info "Moving to friend."
				move_to friend[0].square 
			end
			return true
		end

		false
	end


	def neighbor_help
		order_dist = order_distance
	
		# Find an attacked neighbour and move in to help
		ai.my_ants.each do |l|
			next if self == l
			next unless l.attacked?
			next if l.collective?	# Collectives can fend for themselves
	
			d = Distance.get self, l.pos	

			# Only help out if current ant has no order,
			# or ant in distress is nearer
			if order_dist and order_dist.dist < d.dist
				# Skip helping friend, we have other things to do
				next
			end
	
			if d.dist == 1 
				$logger.info { "#{ self } moving in - next to friend #{ l }." }
				stay
				break
			elsif d.in_view?
				$logger.info { "#{ self } moving in to help attacked buddy #{ l }." }
				move_to l.pos
				break
			end
		end
	end


	def handle_conflict
		# If we can complete the order before being in conflict, 
		# the order will take precedence.
		return if check_orders

		if ai.kamikaze?
			# Pick the nearest enemy and go for it
			$logger.info "Banzai!"
			enemy = closest_enemy
			unless enemy.nil?
				move_to enemy.square
				return
			end
		end
	
		if attacked? and attack_distance.in_peril?
			$logger.info "#{ self } in conflict!"
if false
	# Conflict handled collectively in Analyze Phase

			if ai.aggresive? and enemies.length == 1
				move attack_distance.attack_dir
				return 
			end
	

			return if neighbor_attack
end

			# when defending a hill, stay put	
			if find_order :DEFEND_HILL
				stay
			else
				# Otherwise, just run away
				retreat
			end
		else
			neighbor_help
		end
	end

	def harvesting?
		has_order :HARVEST
	end

	def next_to_enemy?
		[ :N, :E, :S, :W ].each do |dir|
			sq = square.neighbor(dir)
			return true if sq.ant? and sq.ant.enemy?
		end
		false
	end

	def to_s
		str = ""
		o = get_first_order
		unless o.nil?
			str = "[ #{ o.to_s } ]"
		end
		"ant_#{id}#{ square.to_s }#{str}"
	end
end

