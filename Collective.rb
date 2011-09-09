
class Collective

	# order of ant movement depends on where they are
	# within the collective
	@@move_order = { 
		:N => [0,1,2,3],
		:E => [1,3,0,2],
		:S => [2,3,0,1],
		:W => [0,2,1,3]
	}

	include Evasion

	def initialize
		@ants = []
		@safe_count = 0
		@do_reassemble = true
		@incomplete_count = 0

		evade_init
	end

	def add a
		@ants << a
	end

	def size
		@ants.length
	end

	def leader? a
		@ants[0] == a
	end

	def remove a
		#disband
		#return

		is_leader = leader? a

		@ants.delete a

		if is_leader
			$logger.info "Removing leader."
			@ants.each do |b|
				b.remove_target_from_order a
			end
		end

		@do_reassemble = true
	end	

	def attack_dir d
		if d.row.abs < 1
			if d.col > 0
				return :E
			else
				return :W
			end
		end
		if d.col.abs < 1
			if d.row > 0
				return :S
			else
				return :N
			end
		end

		if d.row.abs < d.col.abs
			if d.row > 0
				return :S
			else
				return :N
			end
		else
			if d.col > 0
				return :E
			else
				return :W
			end
		end
	end

	def can_pass? dir
		order = @@move_order[ dir ]

		ok = true
		order[0,2].each do |n|
			a = @ants[n]
			next if a.nil?	# TODO: if ant is missing, can we still pass?
			next unless in_location? a, n

			ok =false and break unless a.can_pass? dir
		end

		ok
	end


	def move_intern dir
		return false unless can_pass? dir

		order dir
		true
	end


	def order dir
		@@move_order[dir].each do |n|
			a = @ants[n]
			next if a.nil?
			#next if a.orders?
			next unless in_location? a, n

			a.move dir
		end
	end


	def can_assemble?
		# TODO: How can following happen????
		return false if @ants[0].nil?

		sq = @ants[0].square

		return false unless ( sq.neighbor( :E ).land? and
		  sq.neighbor( :S ).land? and
		  sq.neighbor( :E ).neighbor( :S ).land?  )

		# Check presence of foreign member on given square
		if @ants[1].nil? or !in_location? @ants[1], 1
			return false if sq.neighbor( :E ).ant?
		end
		if @ants[2].nil? or !in_location? @ants[2], 2
			return false if sq.neighbor( :S ).ant?
		end
		if @ants[3].nil? or !in_location? @ants[3], 3
			return false if sq.neighbor( :E ).neighbor(:S).ant?
		end
	
		return true	
	end


	def move
		leader = @ants[0]
		return if leader.moved?
	
		return if evading
		return if incomplete
		return if safe
		reassemble

		dist = attack_distance

		if dist and dist.in_view?
			dir = nil
			if !assembled?
				# retreat
				dir = dist.invert.dir
			else
				dir = attack_dir( dist )
			end

			if !move_intern dir 
				evade dir
				## We may be stuck - do something random
				#move_intern [ :N, :E, :S, :W ][ rand(4) ]
			end
		else
			if assembled?
				# We're in place but not attacked.
				# go pick a fight if possible
				d = closest_enemy leader, leader.ai.enemy_ants 

				# If more or less close, go for it
				if d and d.dist < 30
					if move_intern d.dir
						# Don't disband when not threatened
						@safe_count = 0
					else
						evade d.dir
					end
				end
			else
				check_assembly

				if !can_assemble?
					# Location is not good, move away
					move_intern [ :N, :E, :S, :W ][ rand(4) ]
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
		leader = @ants[0]
		return true if a == leader

		# NOTE: the from-square of the ant is used!
		a.square == Coord.new( (leader.row + count/2), (leader.col + count%2) )
	end

	def assembled?
		return false unless filled?

		leader = @ants[0]

		count = 0
		okay = true
		@ants.each do |a|
			unless in_location? a, count
				okay = false
				break
			end
			count += 1
			#break if count >= 4
		end

		okay
	end

	#
	# members may have drifted. Ensure that they are in the right place
	#
	def check_assembly
		ok = true

		leader = @ants[0]
		return if leader.nil?

		count = 1
		@ants.each do |a|
			next if a === leader

			unless a.nil? or a.orders?
				unless in_location? a, count
					a.set_order( leader, :ASSEMBLE, [ count/2 , count % 2 ] )
					ok = false
				end
			end

			count += 1
		end
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
				a.set_order( leader, :ASSEMBLE, [ count/2 , count % 2 ] ) 
			end

			count += 1
		end
	
	end

	def incomplete
		if size < 4 
			@incomplete_count += 1
		else
			@incomplete_count = 0
		end

		if @incomplete_count > 30
			disband
		end

		( @incomplete_count > 30 )
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

		if @safe_count > 20
			disband
			ret = true
		end

		ret
	end


	def attack_distance
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
		size == 4
	end
end
