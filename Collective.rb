

class Collective

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

	def square
		@ants[0].square
	end

	def size
		@ants.length
	end


	def filled?
		size == fullsize 
	end


	#
	# Order the given ant to the specified position within the collective.
	# If no position given, add to the end of the collective.
	#
	def rally ant, count = nil
		count = size() -1 if count.nil?
		ant.set_order( leader.square, :ASSEMBLE, relpos(count) ) 
	end

	def to_s
		"collective [#{ @ants.join(", ") }]"
	end

	def leader? a
		@ants[0] == a
	end

	def move
		catch (:done) do 
			return if leader.moved?
	
			test_incomplete
			reassemble unless assembled?
			return if evading
			test_safe

			move2
		end
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
			catch (:done) do 
				disband
			end
		else
			@do_reassemble = true
		end
	end	


	#
	# Break up collective and let the ants go
	# their individual way
	#
	def disband
		$logger.info "Disbanding #{ self }"
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

		# Collective doesn't exist any more. Skip any other statements
		$logger.info "Doing throw because collective disbanded."
		throw :done
	end


	def assembled? side_effect = true
		return false unless filled?

		count = 0
		okay = true
		@ants.each do |a|
			if in_location? a, count
				# Note: following is a side effect.
				#       For the logic, this is the best place to put it.
				if side_effect
					#a.clear_orders if a.orders?
					a.evade_reset if a.evading?
				end
			else
				okay = false
				# Don't break here; if-block needs to be done for all members
			end
			
			count += 1
		end

		okay
	end


	def add_recruit a
		return if assembled? false

		if filled?
			# Check if new recruit is nearer to the leader than one
			# of the current members
			# BUG: [1...size].each do |n|
			#    - member below became an array of ants
			#        TODO: Examine why
			dista = Distance.new leader, a

			# Pick best member to replace
			bestn = nil
			bestdist = nil
			max = size() -1
			(1..max).each do |n|
				member = @ants[n]

				next if in_location? member, n

				distn = Distance.new leader, member

				if dista.dist < distn.dist	
					if bestdist.nil? or distn.dist < bestdist
						bestn = n
						bestdist = distn.dist
					end
				end
			end

			unless bestn.nil?
				member = @ants[bestn]

				$logger.info "Collective #{ leader.to_s } replacing assembling member #{ member.to_s } n #{ bestn }, dist #{ bestdist }, with #{ a.to_s }, dist #{ dista.dist }"

				# Replace current member with new ant
				member.clear_orders
				member.set_collective nil

				a.clear_orders
				@ants[bestn] = a
				a.set_collective self
				rally a

			end

			return assemble

		else
			add a
			a.set_collective self 
			rally a
			return assemble
		end
	end


###########################
# Top-level strategies
###########################


	def self.recruit ant
		# recruit near neighbours for a collective
		if ant.ai.defensive?
			friend_distance = 10
		else
			friend_distance = 20
		end
	
		recruits = ant.neighbor_friends friend_distance 
		recruits.delete_if { |a| a.collective? }
	
		# If there are enough, make the collective
		if recruits.size > 0 
			recruits.each do |l|
				ant.add_collective l, recruits.length
				break if ant.collective_assembled?
			end
			$logger.info "Created #{ ant.collective.to_s}"
		else
			# If not enough close by, disband the collective
			# These may then be used for other incomplete collectives
			catch :done do
				ant.collective.disband if ant.collective?
			end
		end
	end


	#
	# Complete existing collectives first
	#
	def self.complete_collectives ai
		ai.my_ants.each do |ant|
			next unless ant.collective? and not ant.collective_leader?

			coll = ant.collective

			next if coll.assembled? false

			if coll.complete? and coll.furthest_follower_distance < 5
				$logger.info { "#{ coll } followers almost there; not re-recruiting" }
				next
			end
			
			$logger.info "Completing #{ coll }."
	
			recruit ant
		end
	end


	#
	# Assemble new collectives
	#
	def self.create_collectives ai
		ai.my_ants.each do |ant|
			next if ant.collective?
			next unless ant.attacked? 
			#next if ant.has_order :RAZE 
	
			# Don't even think about assembling if not enough ants around
			next if ant.ai.my_ants.length < AntConfig::ASSEMBLE_LIMIT
	
			if ant.ai.defensive? 
				# If collective nearby, don't bother creating a new one
				collective_near = false
				ant.neighbor_friends( 10 ).each do |a|
					if a.collective?
						$logger.info "#{ ant.to_s } has collective nearby"
						collective_near = true
						break
					end
				end
	
				next if collective_near
			end
	
			# If too close too an assembling collective, 
			# don't bother creating a new one
			collective_near = false
			ant.neighbor_friends( 3 ).each do |a|
				if a.collective?
					$logger.info "#{ ant.to_s } assembling collective too close "
					collective_near = true
					break
				end
			end
			next if collective_near

			recruit ant
		end
	end


	def self.move_collectives ai	
		# Move collectives as a whole
		ai.my_ants.each do |ant|
			next unless ant.collective_leader?

			$logger.info "Moving collective."	
			ant.move_collective
		end
	end

###########################
# End Top-level strategies
###########################

	#
	# Placeholder for assembly
	#
	def assemble
		false
	end


	#
	# Determine best move in conflict between single collective2
	# and multiple enemies.
	#
	# No other neighboring friends are taken into account.
	#
	# Pre: Collective must be assembled.
	#
	def analyze_attack()
		enemies = []
		guess = []
		harmless = true
		leader.enemies_in_view.each do |e|
			adist = Distance.new( leader.pos, e.pos)
			break unless adist.in_peril?

			harmless &&= ( e.twitch? or e.stay? )
			enemies << e 

			guess << e.guess_next_pos
		end
		return false if guess.length == 0

		$logger.info { "Enemies in peril distance: #{ enemies }" }
		$logger.info { "Enemies guess next pos: #{ guess }" }

		# Generate all possible movements of current collective
		moves = {} 

		lam = lambda do |dir| 
			# Test movement of collective
			if can_pass? dir
				moves[ dir ] = @ants.collect { |a| a.square.neighbor dir }
			end
		end

		# Note that we don't bother with orientation so close to conflict	

		if harmless
			$logger.info { "#{ self } attackers harmless; staying is not an option" }
		else
			moves[ :STAY ] = @ants.collect { |a| a.square }
		end
		lam.call :N
		lam.call :E
		lam.call :S
		lam.call :W

		$logger.info { "possible moves: #{ moves }" }
		return false if moves.length == 0

		# calculate the body count for all possible moves
		# Select the best result
		best_dir = nil
		best_dead = nil
		count = 0
		moves.each_pair do |dir, move|
			$logger.info "Analyzing direction #{ dir }"
			dead = analyze_hits guess, move

			if  best_dir.nil? or
				( dead[0] == 0 and dead[1] > best_dead[1] ) or
				( dead[0] == 0 and best_dead[0] > 0 ) or
				( dead[0] < best_dead[0] )

				best_dir = dir
				best_dead = dead
				count = 1
			else 
				if dead[0] == best_dead[0] and dead[1] == best_dead[1] 
					count += 1
				end
			end
		end

		$logger.info { 
			if best_dir.nil?
				"No best move!"
			elsif count == moves.length
				"All moves are valid"
			else
				"Best move: #{ best_dir }; friends dead: #{ best_dead[0] }, enemies dead: #{ best_dead[1] }"
			end
		}

		# In the case of all moves valid or no moves at all, let the old logic handle it.
		return false if best_dir.nil? or count == moves.length
		best_dir
	end


	def analyze_hits guess, move
		# Now, analyze the hits between the ants
		# Note that no distinction is made between various enemies
		enemy_hits = {}
		friend_hits = {}
		guess.each_index do |e|
			move.each_index do |f|
				dist = Distance.new( guess[e], move[f])
				#$logger.info "dist: #{ dist }, #{ dist.dist}"
				if dist.in_attack_range?
					#$logger.info "In attack range"
					if enemy_hits[e].nil?
						enemy_hits[e] = [f]
					else
						enemy_hits[e] << f
					end
					if friend_hits[f].nil?
						friend_hits[f] = [e]
					else
						friend_hits[f] << e
					end
				end
			end
		end

		return [0,0] if enemy_hits.length == 0
		
		$logger.info { "enemy hit results: #{ enemy_hits }" }
		$logger.info { "friend hit results: #{ friend_hits }" }

		# Analyze
		enemy_dead = 0
		friend_dead = 0
		enemy_hits.each_pair do |k,list|
			list.each do |v|
				if list.length >= friend_hits[v].length
					enemy_dead += 1
					break
				end
			end 
		end

		friend_hits.each_pair do |k,list|
			list.each do |v|
				if list.length >= enemy_hits[v].length
					friend_dead += 1 
					break
				end
			end 
		end
		$logger.info { "Conflict result : friends dead: #{ friend_dead }, enemies dead: #{ enemy_dead }" }

		[ friend_dead, enemy_dead]
	end

	def complete?
		size == fullsize 
	end

	# Pre: collective complete
	def furthest_follower_distance
		leader = @ants[0]

		#$logger.info " ants: #{ @ants }"

		found_dist = nil
		@ants[1..-1].each do |ant|
			d = Distance.new leader, ant

			if found_dist.nil? or d.dist > found_dist
				found_dist = d.dist
			end
		end

		found_dist
	end


	private

	def leader
		@ants[0]
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
			next unless in_location? a, n

			a.move dir
		end

		# Actually, you would have to check if ants orders
		# were accepted. So following line is a little lie.
		true
	end


	def hold_ground dist
		$logger.info "#{ self.to_s} holding ground"

		# Allow sideways movement for better conflict placement
		dir = dist.shortest_dir
		if dir.nil? 
			stay
		else
			$logger.info "#{ self.to_s } placement to #{ dir }."
			# Note: don't do evasion here, we're holding ground
			# and don't want to move away
		end
		throw :done
	end


	def stay_away enemy, dist

		if dist.in_peril?
			# retreat if too close for comfort
			dir = dist.invert.dir

			if enemy.straight_line? and not enemy.advancing? leader.pos
				# possibly ignoring you; change direction
				$logger.info "Evading ignorer"
				dir = left dir
			end
		else
			hold_ground dist
		end
		dir
	end

	def move2
		dist = attack_distance

		$logger.info "#{ self.to_s } dist: #{ dist.to_s }"
		if dist and dist.in_view?
			# It is possible to approach an anthill completely and 
			# be right next to the emerging enemy ants. Following ensures
			# that the collective will not try to evade.
			if dist.dist == 1 
				stay
				throw :done
			end

			# Conflict; enemy is in view range
			enemy = leader.closest_enemy

			unless enemy
				# Safefuard; Following problem has occured more than once
				$logger.info "WARNING: attack_distance defined but no closest enemy present."
				return
			end

			dir = nil
			if !assembled?
				$logger.info "#{ self.to_s } not assembled"

				# If followers are close, don't move
				if size == fullsize and furthest_follower_distance < 3
					$logger.info "#{ self.to_s } almost assembled. waiting"
					leader.stay
					return
				end

				if not leader.has_order :DEFEND_HILL
					dir = stay_away enemy, dist
				else
					# Advance up to peril distance
					hold_ground dist if dist.in_peril?
				end
			else
				dir = analyze_attack
				unless dir === false
					if dir == :STAY
						stay
						return
					else
						# Note that evading is not taken into account
						# It is excluded in analyze_attack with test of can_pass?
						move_intern dir 
						return
					end
				end

				dir = dist.attack_dir
				$logger.info "Attack dir #{ leader.to_s }: #{ dir }"

				# TODO: changing orientation can also be caught by twitchers
				#		eg. if two twitchers alternate in being the closest
				return if orient dist.longest_dir


				# If there is only one enemy, attack always.

				enemies = leader.enemies_in_view
				if enemies.length() > 1 and leader.ai.defensive? 

					if enemies.length > size() -1 and not leader.has_order :DEFEND_HILL
						$logger.info "#{ leader.to_s} too many enemies"
						dir = stay_away enemy, dist
					else
						# Advance up to peril distance
						hold_ground dist if dist.in_peril?
					end
				else
					if enemy.straight_line? and not enemy.advancing? leader.pos
						# This is an ant ignoring you and moving in a fixed direction
						# Don't bother chasing if it's not moving toward you
						$logger.info "Not chasing straight liner. #{ enemy.to_s } going #{ enemy.dir }"

						# for good measure, move in the opposite direction of
						# the enemy ant; there may be more coming.
						move_intern reverse( enemy.dir )
						throw :done

						# TODO: Perhaps concentrate on the next closest ant
					end

					if enemy.twitch?
						# break the twitch, otherwise we'll be twitching in unison forever
						$logger.info "Breaking the twitch."
						# Just plain attack
						dir = dist.longest_dir
					end

					if dist.in_peril? and not dist.in_danger?
						$logger.info "In peril"
						# Enemy is now two squares away from attack distance.
						# With an attacking enemy, now is a bad time to advance.
						# Skip a turn so we can hit with extra force the next turn.
						if enemy.advancing? leader.pos
							hold_ground dist
						end
					end
				end
			end

			if !move_intern dir 
				# Actual dir will be different

				# Collectives don't evade any more
				# TODO: Find a way for pathfinder to work with collectives
				#dir = evade dir
				stay
			end
		else
			$logger.info "#{ leader.to_s } no attacker"


			if !leader.ai.defensive? and assembled?
				# We're in place but not attacked.
				# go pick a fight if possible
				$logger.info "picking a fight"
				d = nil 
				enemy = leader.closest_enemy
				d = Distance.new( leader, enemy ) unless enemy.nil?

				# If more or less close, go for it
				if d and d.dist < AntConfig::FIGHT_DISTANCE 

					if enemy.straight_line? and not enemy.advancing? leader.pos
						$logger.info "Not chasing straight liner 2."
						move_intern d.invert.dir
						throw :done

					end

					# Don't disband when not threatened
					@safe_count = 0
					return if orient d.longest_dir
					unless move_intern d.dir
						# Collectives don't evade any more
						# TODO: Find a way for pathfinder to work with collectives
						#dir = evade d.dir
						stay
					end
				end
			elsif assembled? and leader.first_order :RAZE
				# WRI TEST: this is a special case, using ant orders
				# to move collectives.
				# TODO: Check that this works OK
				o = leader.get_first_order
				to = o.handle_liaison( leader.square, leader.ai )
				d = Distance.new( leader, to ) 

				#if d.in_view?

					$logger.info { "Moving #{ self } to raze target #{ to}, dir #{ d.dir}" }
					move_intern d.dir
					throw :done
				#end
			else
				check_assembly

				if !can_assemble?
					# Location is not good, move away
					random_move
				else
					#if not assembled yet, wait for the missing ants to join
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

		if a.abspos.nil?
			a.abspos = leader.square.rel( relpos( count) )
		end

		# NOTE: the from-square of the ant is used!
		a.square == a.abspos 
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

	def test_incomplete
		if size < fullsize 
			@incomplete_count += 1
		else
			@incomplete_count = 0
		end

		if @incomplete_count > AntConfig::INCOMPLETE_LIMIT
			disband
		end
	end


	def test_safe
		tmp = false
		@ants.each do |a|
			return if a.has_order :ASSEMBLE

			if a.attacked?
				tmp = true 
				break
			end
		end

		if tmp 
			@safe_count = 0
		else
			@safe_count += 1
		end

		if @safe_count > AntConfig::SAFE_LIMIT
			$logger.info "We're safe"
			disband
		end
	end


	def attack_distance
		# Do from leader only
		ret = nil
		if leader.attacked? 
			ret = leader.attack_distance
		end

		ret
	end


	def random_move
		$logger.info "Doing random move."
		moves = [ :N, :E, :S, :W, :N, :E, :S, :W ]

		#
		# Given random move may be not passable.
		# Following searches for the next passable direction.
		# If not found, give up
		#
		moves[rand(4),4].each do |dir|
			return if move_intern dir
		end

		# Can not move at all - give up
		disband
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
		return false if [:E,:W].include? d and [:E,:W].include? @orient_dir
		return false if [:N,:S].include? d and [:N,:S].include? @orient_dir

		$logger.info "Switching #{ leader.to_s } from #{ @orient_dir } to #{ d }"

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
		if @ants[n0].can_pass?( move0 )		# DON't test second ant, it is  moving to the position of the first ant.
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

	
	def assemble
		if filled?
			d = Distance.new @ants[0], @ants[1]

			if d.dist == 1
				if d.row == 0
					@orient_dir = :N
					if d.col == -1
						@ants[0], @ants[1] = @ants[1], @ants[0]
					end
				elsif d.col == 0
					@orient_dir = :E
					if d.row == -1
						@ants[0], @ants[1] = @ants[1], @ants[0]
					end
				end

				$logger.info "Collective2 assembled as #{ @ants }, orient #{ @orient_dir}"
				@ants.each { |a|
					[ :ASSEMBLE, :EVADE_GOTO ].each do |o|
						a.clear_order o
					end
				}

				# Ensure that the ants don't drift away
				if @ants[0].moved? and not @ants[1].moved?
					@ants[1].stay
				elsif not @ants[0].moved? and @ants[1].moved?
					@ants[0].stay
				end

				true
			end
		end	

		false
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
		$logger.info "Collective3 #{ leader.square.to_s } relpos count: #{count}, orient: #{ @orient_dir}"
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


	alias :super_move_intern :move_intern
	def move_intern dir
		if @orient_dir == :intern
			return orient dir
		end

		super dir
	end



	def orient d
		# Collective could have been disbanded in the meantime
		return true unless filled?

		return false if [:E,:W].include? d and [:E,:W].include? @orient_dir
		return false if [:N,:S].include? d and [:N,:S].include? @orient_dir
		$logger.info "Switching #{ leader.to_s } from #{ @orient_dir } to #{ d }"

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
			# Can't move to/from intern config
			$logger.info "Collective3 stuck while turning."

			# Can't use random_move or local intern_move here, 
			# orient will be called again and there is danger of
			# running out of stack.

			[ :N, :E, :S, :W ].each do |dir|
				return true if super_move_intern dir
			end

			# Can not move at all - give up
			disband
			# After this point, the collective is empty.
			# Need to get the hell out

			# Note that true is still returned, so as not
			# to confuse calling logic, even if this is 
			# not an actual move.

			# Geez, this was a lousy bug. Added commenting
			# in this part post-mortem.
		else
			@ants[0].stay	# Center ant needs to stay put,
							# could evade otherwise
		end

		moved
	end

end
