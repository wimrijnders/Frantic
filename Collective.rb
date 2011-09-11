
class Collective
	SAFE_LIMIT       = 5 
	INCOMPLETE_LIMIT = 15
	FIGHT_DISTANCE   = 20

	def initialize
		@ants = []
		@safe_count = 0
		@do_reassemble = true
		@incomplete_count = 0
		evade_init
	end

	include Evasion

	def add a
		@ants << a
	end

	def size
		@ants.length
	end

	def leader? a
		@ants[0] == a
	end

	def leader
		@ants[0]
	end

	#
	# Order the given ant to the specified position within the collective.
	# If no position given, add to the end of the collective.
	#
	def rally ant, count = nil
		count = size() -1 if count.nil?
		ant.set_order( leader, :ASSEMBLE, relpos(count) ) 
	end

	def remove a
		is_leader = leader? a

		@ants.delete a

		if is_leader
			$logger.info "Removing leader."
			@ants.each do |b|
				b.remove_target_from_order a
			end
		end

		if size == 1
			disband
		else
			@do_reassemble = true
		end
	end	

	def move_intern dir
		return false unless can_pass? dir

		order dir
		true
	end

	def can_assemble?
		sq = @ants[0].square

		# Check presence of foreign member on given square
		(1..fullsize).each do |n|
			sq_rel =  sq.rel( relpos(n) )
			return false unless ( sq_rel ).land?

			if @ants[n].nil? or !in_location? @ants[n], n
				return false if sq_rel.ant?
			end
		end
	
		return true	
	end

	def assembled?
		return false unless filled?

		count = 0
		okay = true
		@ants.each do |a|
			if in_location? a, count
				# Note: following is a side effect.
				#       For the logic, this is the best place to put it.
				a.clear_orders if a.orders?
				a.evade_reset if a.evading?
				# End side effect
			else
				okay = false
				# Don't break here; if-block needs to be done for all members
			end
			
			count += 1
		end

		okay
	end

	def can_pass? dir #, water_only = false
		water_only = false

		ok = true
		pass_check(dir).each do |n|
			a = @ants[n]
			next if a.nil?	# TODO: if ant is missing, can we still pass?
			next unless in_location? a, n

			if water_only
				ok =false and break if a.square.neighbor(dir).water?
			else
				ok =false and break unless a.can_pass? dir
			end
		end

		ok
	end

	def order dir
		move_list(dir).each do |n|
			a = @ants[n]
			next if a.nil?
			#next if a.orders?
			next unless in_location? a, n

			a.move dir
		end
	end


	def move
		return if leader.moved?
	
		return if incomplete
		reassemble
		return if evading
		return if safe

		dist = attack_distance

		#
		# NOTE: Following distance stategy does not take switching of opponents
		#       into account. TODO: Fix this if strategy proves viable.
		#
		$logger.info "#{ @ants[0].square.to_s } dist: #{ dist.to_s }"
		if dist and dist.in_view?
			dir = nil
			if !assembled?
				$logger.info "#{ @ants[0].square.to_s } not assembled"
				if dist.in_peril?
					# retreat if too close for comfort
					dir = dist.invert.dir
				else
					@prev_dist = dist.clone
					stay
					return
				end
			else
				dir = dist.attack_dir
				$logger.info "Attack dir #{ @ants[0].square.to_s }: #{ dir }"
				return if orient dist.longest_dir

				if dist.in_peril? and not dist.in_danger?
					$logger.info "In peril"
					# Enemy is now two squares away from attack distance.
					# For an aggresive enemy, now is a bad time to advance.
					# Skip a turn so we can hit with extra force the next turn.
					if @prev_dist and dist.longest_dist.abs < @prev_dist.longest_dist.abs()
						$logger.info "Staying put"
						@prev_dist = dist.clone
						stay
						return
					end
				end
			end

			@prev_dist = dist.clone
			if !move_intern dir 
				# Note that actual dir will be different
				# prev_dist will be incorrect
				evade dir
			else
				@prev_dist.adjust dir
			end
		else
			$logger.info "#{ @ants[0].square.to_s } no attacker"
			@prev_dist = nil

			if assembled?
				# We're in place but not attacked.
				# go pick a fight if possible
				d = closest_enemy leader, leader.ai.enemy_ants 

				# If more or less close, go for it
				if d and d.dist < FIGHT_DISTANCE 
					# Don't disband when not threatened
					@safe_count = 0
					return if orient d.longest_dir
					unless move_intern d.dir
						evade d.dir
						# This is a good idea for cramped maps, bad idea for open maps.
						# how to diferentiate?
						#if can_pass? d.dir, true
						#	stay
						#else
						#	evade d.dir
						#end
					end
				end
			else
				check_assembly

				if !can_assemble?
					# Location is not good, move away
					random_move
				else
					#if not assembled yet, wait for the missing ants
					#to join
					stay
				end
			end
		end
	end


	def stay
		@ants.each do |a|
			next if a.nil?
			next if a.moved?
			next if a.orders?

			a.stay
		end
	end


	def in_location? a, count
		return true if count == 0 

		# NOTE: the from-square of the ant is used!
		#a.square == Coord.new( (leader.row + count/2), (leader.col + count%2) )
		a.square == leader.square.rel( relpos( count) )
	end

	#
	# members may have drifted. Ensure that they are in the right place
	#
	def check_assembly
		ok = true

		return false if leader.nil?

		count = 1
		@ants.each do |a|
			next if a === leader

			unless a.nil? or a.orders?
				unless in_location? a, count
					rally a, count
					ok = false
				end
			end

			count += 1
		end

		ok
	end


	#
	# Do a forced reassembly, if the constituency of a collective
	# has changed
	#
	def reassemble
		return unless @do_reassemble
		@do_reassemble = false

		leader = nil

		disband and return if size == 1
	
		count = 1	
		@ants.each do |a|
			if leader.nil?
				leader = a 
				leader.clear_orders
				next 
			end

			if !in_location? a, count
				rally a, count
			end

			count += 1
		end
	
	end

	def incomplete
		if size < fullsize 
			@incomplete_count += 1
		else
			@incomplete_count = 0
		end

		if @incomplete_count > INCOMPLETE_LIMIT
			disband
			true
		else false
		end

	end


	def safe
		ret = false
		tmp = false
		@ants.each do |a|
			tmp = true and break if a.attacked? and not a.orders?
		end

		if tmp 
			@safe_count = 0
		else
			@safe_count += 1
		end

		if @safe_count > SAFE_LIMIT
			disband
			ret = true
		end

		ret
	end


	def attack_distance
		# Do from leader only
		ret = nil
		if leader.attacked? # and not leader.orders?
			ret = leader.attack_distance
		end

# :-( false was last statement so that was returned when 'ret' not present
if false
		best = nil
		@ants.each do |a|
			if a.attacked? and not a.orders?
				tmp = a.attack_distance

				if !best or tmp.dist < best.dist
					best = tmp
				end
			end
		end

		best
end

		ret
	end


	def disband
		$logger.info "Disbanding"
		leader = nil
		@ants.each do |a|
			if leader.nil?
				leader = a
				a.clear_orders
				a.collective = nil
			else
				a.collective = nil
				a.remove_target_from_order leader
			end
		end

		@ants = []
	end

	def filled?
		size == fullsize 
	end

	def random_move
		move_intern [ :N, :E, :S, :W ][ rand(4) ]
	end
end


class Collective4 < Collective

	# order of ant movement depends on where they are
	# within the collective
	@@move_order = { 
		:N => [0,1,2,3],
		:E => [1,3,0,2],
		:S => [2,3,0,1],
		:W => [0,2,1,3]
	}


	def initialize
		super
	end

	def fullsize; 4; end

	def relpos count
		[ count/2 , count % 2 ] 
	end

	def pass_check dir
		@@move_order[dir][0,2]
	end

	def move_list dir
		@@move_order[dir]
	end

	def orient d; false; end
end


class Collective2 < Collective

	# order of ant movement depends on where they are
	# within the collective
	@@move_orderNS = { 
		:N => [0,1],
		:E => [1,0],
		:S => [0,1],
		:W => [0,1]
	}

	@@move_orderEW = { 
		:N => [0,1],
		:E => [0,1],
		:S => [1,0],
		:W => [0,1]
	}



	def initialize
		super
		$logger.info "Creating Collective2"
		@orient_dir = :N
	end

	def fullsize; 2; end

	def relpos count
		return [0,0] if count == 0

		if [:E,:W].include? @orient_dir
			[1,0]
		else
			[0,1]
		end
	end

	def pass_check dir
		if [:E,:W].include? @orient_dir
			if [ :E, :W].include? dir
				@@move_orderEW[dir]
			else
				@@move_orderEW[dir][0,1]
			end
		else
			if [ :E, :W].include? dir
				@@move_orderNS[dir][0,1]
			else
				@@move_orderNS[dir]
			end
		end
	end


	def move_list dir
		if [:E,:W].include? @orient_dir
			@@move_orderEW[dir]
		else
			@@move_orderNS[dir]
		end
	end

	def orient d
		# If orientations compatible, don't bother switching.
		if [:E,:W].include?( d) and [:E,:W].include?( @orient_dir )
			return false
		end
		return false if [:N,:S].include? d and [:N,:S].include? @orient_dir
		$logger.info "Switching #{ @ants[0].square.to_s } from #{ @orient_dir } to #{ d }"

		if [:N,:S].include? d
			# Switch to NS orientation

			n0, n1 = 0,1
			move0, move1 = :W,:N
		else
			# Switch to EW orientation
			# ant 1 needs to move first!
			n0, n1 = 1, 0
			move0, move1 = :S, :E
		end

		# switch orientation
		if @ants[n0].can_pass?( move0 )		# DON't test second ant, it moving to the position of the first ant.
			@ants[n0].move move0 
			@ants[n1].move move1 
			@orient_dir = d
		else
			# Can't switch, just do something
			$logger.info "Can't switch."
			random_move
		end

		true		
	end
end


class Collective3 < Collective

	# order of ant movement depends on where they are
	# within the collective
	@@move_orderNS = { 
		:N => [0,1,2],
		:E => [2,0,1],
		:S => [0,1,2],
		:W => [1,0,2]
	}

	@@move_orderEW = { 
		:N => [1,0,2],
		:E => [0,1,2],
		:S => [2,0,1],
		:W => [0,1,2]
	}



	def initialize
		super
		$logger.info "Creating Collective3"
		@orient_dir = :N
	end

	def fullsize; 3; end

	def relpos count
		$logger.info "Collective3 relpos count: #{count}, orient: #{ @orient_dir}"
		return [0,0] if count == 0

		if [:E,:W].include? @orient_dir
			if count == 1
				[-1,0]
			else
				[1,0]
			end
		elsif [:N,:S].include? @orient_dir
			if count == 1
				[0,-1]
			else
				[0,1]
			end
		else
			# intern
			if count == 1
				[-1,-1]
			else
				[1,1]
			end
		end
	end


	def pass_check dir
		ret = nil

		if [:E,:W].include? @orient_dir
			if [ :E, :W].include? dir
				ret = @@move_orderEW[dir]
			else
				ret = @@move_orderEW[dir][0,1]
			end
		elsif [:N,:S].include? @orient_dir
			if [ :E, :W].include? dir
				ret = @@move_orderNS[dir][0,1]
			else
				ret = @@move_orderNS[dir]
			end
		else
			# intern config - check all ants
			ret = [0,1,2]
		end

		$logger.info "pass_check dir #{dir}, orient: #{ @orient_dir } returning #{ ret.to_s }"
		ret
	end


	def move_list dir
		if [:E,:W].include? @orient_dir
			@@move_orderEW[dir]
		elsif [:N,:S].include? @orient_dir
			@@move_orderNS[dir]
		else
			[0,1,2]
		end
	end


	def orient d
		return false if [:E,:W].include? d and [:E,:W].include? @orient_dir
		return false if [:N,:S].include? d and [:N,:S].include? @orient_dir
		$logger.info "Switching #{ @ants[0].square.to_s } from #{ @orient_dir } to #{ d }"

		moved = false
		if @orient_dir != :intern
			# switch to intern first
			$logger.info "Switching to intern config."
			if [:N,:S].include? @orient_dir
				if @ants[1].can_pass? :N and @ants[2].can_pass? :S
					@ants[1].move :N 
					@ants[2].move :S
					@orient_dir = :intern
					moved = true
				end
			else
				if @ants[1].can_pass? :W and @ants[2].can_pass? :E
					@ants[1].move :W 
					@ants[2].move :E
					@orient_dir = :intern
					moved = true
				end
			end

		else
			if [:N,:S].include? d
				if @ants[1].can_pass? :S and @ants[2].can_pass? :N
					@ants[1].move :S 
					@ants[2].move :N
					@orient_dir = d
					moved = true
				end
			else
				if @ants[1].can_pass? :E and @ants[2].can_pass? :W
					@ants[1].move :E 
					@ants[2].move :W
					@orient_dir = d
					moved = true
				end
			end
		end

		unless moved
			# Can't move to intern config
			random_move
		end
		moved
	end

	def move_intern dir
		if @orient_dir == :intern
			orient dir
			return
		end

		super dir
	end
end
