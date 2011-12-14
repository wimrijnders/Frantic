
class Order
	attr_accessor :order, :offset

	def initialize square, order, offset = nil
		@square = square
		@order = order
		@offset = offset
		@liaison = nil
	end

	def square
		sq = @square

		if @square.respond_to? :square
			sq = @square.square
		end

		if @offset.nil?
			sq
		else
			sq.rel @offset
		end
	end


	def to_s
		str = ""
		unless @offset.nil?
			str = ", offset #{ @offset }"
		end

		"Order #{ order }, #{ @square }#{ str }"
	end

	def square= v
		@square = v
	end

	def sq_int
		@square
	end

	def target? t
		@square == t
	end

	def == a
		sq_int.class ==a.sq_int.class and 	# target square can have differing classes
		sq_int.row == a.sq_int.row and		
		sq_int.col == a.sq_int.col and
		order == a.order and
		( ( offset.nil? and a.offset.nil? ) or
		  (	offset[0] == a.offset[0] and offset[1] == a.offset[1] )
		)
	end

	def add_offset offs
		if @offset.nil?
			@offset = offs
		else
			@offset[0] += offs[0]
			@offset[1] += offs[1]
		end
	end

	def clear_liaison
		@liaison = nil
	end

	def handle_liaison cur_sq, ai
		sq = square

		if @liaison
			# First condition is to keep on moving to final target, 
			# when all liaisons are passed.
			if @liaison != sq and ( @liaison == cur_sq or $region.clear_path(cur_sq, @liaison ) )
				$logger.info { "Order #{ order } clear path to liaison #{ @liaison }" }
				@liaison = nil
			end
		end

		unless @liaison
			liaison  = $region.path_direction cur_sq, sq
			if liaison.nil?
				$logger.info { "WARNING: No liaison for order #{ order } to target #{ sq }" }

				# We must have drifted off the path - restart search
				Region.add_searches sq, [ cur_sq ], true 

				# Don' specify move at this moment
				return nil

			elsif false === liaison
				$logger.info "no liaison needed - move directly"
				# Note that we use the liaison member for the target move
				@liaison = sq
			else
				@liaison = liaison
			end
		end

		$logger.info { "current #{ cur_sq } moving to #{ @liaison }" }
		ai.map[ @liaison.row][ @liaison.col ]
	end
end


module Orders

	def orders_init
		@orders = []
	end

	private

	Order_priority = [
		:EVADE_GOTO,
		:FORAGE,
		:ATTACK,
		:ASSEMBLE,
		:DEFEND_HILL,
		:RAZE,
		:DEFEND,
		:GOTO,
		:HARVEST
	]

	def sort_orders
		ai.turn.check_maxed_out

		$logger.info {
			str = ""
			@orders.each do |o|
				str << "#{o }" + ", "
			end
			"Sorting orders pre: " + str
		}

		# if none of the following orders present, then GOTO and FORAGE have equal standing
		other_present = true
if false
		other_present = false
		[ :ATTACK, :ASSEMBLE, :DEFEND_HILL, :RAZE, :DEFEND ].each do |order|
			if has_order order
				other_present = true
				break	
			end
		end
end

		# Nearest orders first
		items = {}
		@orders.each { |a| 
			items[a] = $pointcache.get self.pos, a.square
		}

		@orders.sort! do |a,b|
			# Food goes before rest
			if ( other_present and a.order == :FORAGE and b.order == :FORAGE ) or
				( not other_present and [ :FORAGE, :GOTO].include? a.order and
				  [:FORAGE, :GOTO ].include? b.order  )

				itema = items[a] 
				itemb = items[b] 

				# valid items first
				if itema.nil? and not itemb.nil?
					1
				elsif not itema.nil? and itemb.nil?
					-1
				elsif itema.nil? and itemb.nil?
					0	
				elsif itema[3] and not itemb[3]
					1
				elsif not itema[3] and itemb[3]
					-1
				else
					itema[0] <=> itemb[0]
				end

			else
				index_a = Order_priority.index a.order
				index_a = Order_priority.length if index_a.nil?

				index_b = Order_priority.index b.order
				index_b = Order_priority.length if index_b.nil?

				index_a <=> index_b
			end
		end

		$logger.info {
			str = ""
			@orders.each do |o|
				str << "#{o.order }" + ", "
			end
			"Sorted orders: " + str
		}
	end

	public

	#
	# Returns true if order added, false otherwise
	# 
	def set_order square, what, offset = nil, from_handle_orders = false
		n = Order.new(square, what, offset)
		#$logger.info { "Trying #{ n } for #{ self.to_s }" }

		if collective_leader? and
		  what == :FORAGE and
		( collective_assembled? or
		  (attacked? and attack_distance.in_peril? )
		) 

			$logger.info { "Collective leader #{ self } doesn't accept order #{ what } while in conflict." }
			return false
		end

		if not $pointcache.can_reach self.square, square
			# ignore order
			$logger.info "#{ self } can't reach target #{ n }"
			return false
		end
		square = n.square


		if square.water?
			$logger.info { "Target #{ square.to_s } is water; determine nearest land" }
			offset = nearest_non_water square
			unless offset.nil?
				$logger.info { "Found land at offset #{ offset }" }
				n.add_offset offset
				square = ai.map[n.square.row][ n.square.col ]
			end
		end
		if square.water?
			$logger.info { "ERROR: Target #{ square.to_s } is still water" }
		end

		@orders.each do |o|
			if o.order == what
				if [ :HARVEST, :DEFEND ].include? what
					$logger.info "Already doing order #{ what }"
					return false
				end
			end

			if o == n
				$logger.info "Order already present"
				return false
			end
		end

		if [ :EVADE_GOTO, :FORAGE, :GOTO ].include? what
			clear_order :EVADE_GOTO 
		end

		if [ :GOTO, :FORAGE ].include? what
			clear_order :GOTO 
			#evade_reset
		end


		$logger.info { "Setting order #{ what } on square #{ square.to_s } for #{ self.to_s }" }

		# ASSEMBLE overrides the rest of the orders
		clear_orders if what == :ASSEMBLE

		# Reset all liaisons of current orders, otherwise 
		# the ant may possibly move in a wrong direction if
		# new order is cleared
		@orders.each { |o| o.clear_liaison }

		@orders.insert 0,n
		evade_reset
		sort_orders


		if ai.turn.maxed_out?
			# Maxed out situation
			# If at all possible, handle orders right away,
			# So that we get as many orders as possible through
			if from_handle_orders
				$logger.info "Called from handle_orders; not recursing"
			else
				handle_orders
			end
		end

		true
	end


	def clear_orders
		p = find_order :HARVEST
		if p
			ai.harvesters.remove self if ai.harvesters
		end

		@orders.each do |o|
			next unless o.order == :FORAGE

			ai.food.remove_ant self, [ o.sq_int.row, o.sq_int.col ]
		end

		@orders = []

		evade_reset
	end

	def clear_order order
		p = find_order  order
		if p 
			if order == :HARVEST
				ai.harvesters.remove self if ai.harvesters
			end
			if order == :FORAGE
				ai.food.remove_ant self, [ p.sq_int.row, p.sq_int.col ]
			end
			$logger.info { "Clearing order #{ order } for #{ self.to_s }." }
			@orders.delete p
			evade_reset
		end
	end

	def orders?
		@orders.length > 0
	end


	def order_distance
		return nil unless orders?

		Distance.get pos, @orders[0].square
	end


	#
	# Delete order aimed at specific square
	#
	def remove_target_from_order t
		p = nil

		if orders?
			@orders.each do |o|
				if o.target? t
					p = o 
					break
				end
			end

			unless p.nil?
				ai.harvesters.remove self if ai.harvesters and p.order == :HARVEST
				if p.order == :FORAGE
					ai.food.remove_ant self, [ p.sq_int.row, p.sq_int.col ]
				end

				$logger.info { "Removing order #{ p.order } from #{ self.to_s }" }
				@orders.delete p
				evade_reset
			end
		end

		# return true if target was present
		!p.nil? 
	end

	def find_order  order
		p = nil
		if orders?
			@orders.each do |o|
				if o.order == order 
					p = o 
					break
				end
			end
		end

		p	
	end


	def clear_first_order del_food = false
		p = @orders[0]
		@orders = @orders[1..-1]
		evade_reset

		if p.order == :FORAGE
			# Note that we do not use the coord with offset here
			if del_food
				ai.food.remove [ p.sq_int.row, p.sq_int.col ]
			else
				ai.food.remove_ant self, [ p.sq_int.row, p.sq_int.col ]
			end
		end
	end


	def change_order sq, order
		p = find_order order

		if p
			$logger.info { "Change order #{ order } to square #{ sq.to_s } for #{ self.to_s }" }
			p.square = sq
			p.offset = nil	if order == :HARVEST
			evade_reset
		else
			$logger.info { "#{ to_s } has no order #{ order}!" }
		end
		
	end

	def handle_orders
		return false if moved?
		return false if collective_assembled?
		ai.turn.check_maxed_out

		# Following happens when razing hills.
		if neighbor_enemies?(2)
			$logger.info { " #{ self } right next to enemy, staying and ignoring orders." }
			stay
			return true
		end


		prev_order = (orders?) ? @orders[0].square: nil

		while orders?
			order_sq    = @orders[0].square
			order_order = @orders[0].order
			$logger.info "Checking order #{ order_order } on #{ order_sq} for #{ self }"

			if order_order == :ATTACK
				d = Distance.get self.square, order_sq 
				if d.in_view?
					unless !ai.map[ order_sq.row][ order_sq.col].ant.nil? and
					       ai.map[ order_sq.row][ order_sq.col].ant.enemy?

						$logger.info { "Clearing attack target #{ order_sq.to_s}." }
						clear_first_order
						next
					end
				end 
			end

			if order_order == :DEFEND_HILL
				d = Distance.get self.square, order_sq 

				# Use of in_peril in order to get closer to hill than in_view
				if d.in_peril?
					# if on hill itself, move away
					if self.square == order_sq
						$logger.info { "Defender moving away from hill #{ order_sq.to_s}." }
						move self.default
						return
					else
						$logger.info { "Defending hill #{ order_sq.to_s}." }
						stay
						return true
					end
				end 
			end


if false
			if order_order == :GOTO
				d = Distance.get self.square, order_sq 

				if ( self.square == order_sq ) or d.dist <= 2
					$logger.info { "GOTO close enough to square #{ order_sq.to_s}." }
					BorderPatrolFiber.clear_target order_sq
					clear_first_order
					next
				end 
			end
end

			if order_order == :DEFEND
				d = Distance.get self.square, order_sq 

				# Use of distance in order to get closer to location than in_view
				if ( self.square == order_sq ) or
				   ( d.in_attack_range? and
				     #Distance.direct_path? self.square, order_sq
				     $pointcache.has_direct_path self.square, order_sq
				   )
					$logger.info { "Defending square #{ order_sq.to_s}." }

					# Note: following may be a bit wasteful to call every time
					# we are in handle orders
					BorderPatrolFiber.clear_target order_sq

					stay
					return true
				end 
			end


			if self.square == order_sq
				# Done with this order, reached the target

				#self.trail.set_trail order_sq  unless order_order == :ASSEMBLE

				if order_order == :RAZE
					$logger.info { "Hit anthill at #{ self.square.to_s }" }

					clear_first_order
					@ai.clear_raze self.square	
					
				else
					$logger.info { "#{ to_s } reached target for order #{ order_order }" }

					if order_order == :GOTO
						BorderPatrolFiber.clear_target order_sq
					end

					if order_order == :HARVEST
						# Keep the order in the list, don't remove
						return true
					else
						clear_first_order ( order_order == :FORAGE )
					end
				end


				next
			end


			if order_order == :GOTO
				unless BorderPatrolFiber.known_region self.square
					$logger.info { "#{ to_s } with order #{ order_order } outside known regions" }

					clear_first_order
					next
				end
			end


			if order_order == :ASSEMBLE
				if !collective
					clear_first_order
					next
				end
			end

			# Check if food still present when in-range
			if order_order == :FORAGE
				sq = order_sq
				str = ""

				result = @ai.food.active? [ sq.row, sq.col ]
				if result.nil?
					# food is already gone. Skip order
					clear_first_order
					str << "not in list!"
					next
				elsif result
					str << "yes"
			
					d = Distance.get self, sq
					if d.dist == 1
						# Special case; sometimes food appears right next to
						# ant (eg first turn next to an anthill). For some reason
						# it does not get consumed immediately
						$logger.info { "#{ self } right next to food #{ sq }." }
						clear_first_order true
						stay
						return true
					end
				else
					d = Distance.get self, sq
					if d.in_view?
						str << "no"
						clear_first_order true
						next
					else
						str << "can't tell, out of view"
					end
				end
				$logger.info { "Food #{ sq } still there: #{ str}" }
			end


			# Check if hill still present when in-range
			if order_order == :RAZE
				sq = order_sq
				str = ""

				closest = closest_ant_view [ sq.row, sq.col], @ai
				unless closest.nil?
					d = Distance.get closest, sq

					if d.in_view? 
						result = @ai.hills.active? [ sq.row, sq.col]

						if result.nil?
							$logger.info "Hill not there!"
						elsif result == true
							str << "yes"
						else
							# hill is dead
							str << "no"

							clear_first_order
							@ai.clear_raze sq
							next
						end
					else
						str << "can't tell, out of view"
					end
				end

				$logger.info { "Hill #{ sq } still there: #{ str}" }
			end


			# check if harvest target is water
			if order_order == :HARVEST and evading?
				sq = order_sq
				d = Distance.get self, sq

				# Use of in_danger here is not because of attack, but because
				# we want to get closer to the target square than in_view
				if d.in_danger? and @ai.map[ sq.row ][sq.col].water?
					$logger.info { "#{ self.to_s } harvest target #{ sq } is water. Can't get any closer" }
					@orders[0].offset = [ -( sq.row - self.row ), - (sq.col - self.col ) ]
					$logger.info { "Set order offset to #{ @orders[0].offset }." }
					stay
					evade_reset
					return true
				end
			end

			break
		end

		return false if !orders?

		if evading?
			if prev_order != @orders[0].square
				# order changed; reset evasion
				$logger.info "#{ self } evasion reset"
				evade_reset
			else
				# Handle evasion elsewhere
				$logger.info "#{ self } evading"
				return false
			end
		end

		if @orders[0].order == :ASSEMBLE
			# NB: method assemble removes :ASSEMBLE and other orders
			#     from collective members
			if collective and collective.assemble
				stay
				evade_reset
				return true
			end
		end

		return false if !orders?


		item = $pointcache.get self.square, order_sq

		to = nil
		if not item.nil? 
			if not item[3]
				$logger.info "Valid pointcache item detected" # #{ item }"
			end

			to = item[2]	# to is a direction
			move to, order_sq
		else
			# This should never happen any more

			$logger.info "WARNING: nil item from pointcache"

			to = @orders[0].handle_liaison( self.square, ai )

			if to.nil? 
				$logger.info "No to-square"
				return false
			else
				move_to to  # to is a square
			end
		end

		$logger.info { 
			"#{ to_s } order #{ order_order } to #{ order_sq }, dir/to #{ to }" 
		}

		true
	end


	#
	# Return true if after check, we are still continuing with orders
	#
	def check_orders
		enemies = enemies_in_view

		catch :done do
			enemies.each do |e|
				while orders?
					# If enemy is closer to order target (foraging only),
					# cancel order
					break unless @orders[0].order == :FORAGE
	
					da = Distance.get( pos, @orders[0].square )
					de = Distance.get( e.pos, @orders[0].square )
	
					if da.dist > de.dist
						# we lucked out - skip this order
						$logger.info { "check_orders #{ to_s } skipping." }
						clear_first_order
					else
						# We can still make it first! Even if we die...
						$logger.info { "check_orders #{ to_s } we can make it!" }
						throw :done
					end
				end
			end
		end

		orders?
	end

	def find_orders what, sq = nil, first_only = false
		list = {}

		count = 0
		@orders.each do |n|
			if n.order == what
				#$logger.info { "found #{ what }" }

				if sq
					# Search for specific target only 
					if sq == n.square 
						$logger.info { "Found order #{ what } on #{ n.square }" }
						list[ sq ] = count
						break
					end
				else
					$logger.info { "Found order #{ what }" }
					list[ n.square ] = count
					break if first_only
				end
			end

			count += 1
		end

		list
	end

	def has_order what, sq = nil
		list = find_orders what, sq, true

		list.length > 0
	end

	def first_order what
		if @orders[0]
			@orders[0].order == what
		else
			false
		end
	end

	def get_first_order
		@orders[0]
	end

	def can_raze?
		not orders? or ( first_order :HARVEST and not has_order :DEFEND_HILL )
	end

end
