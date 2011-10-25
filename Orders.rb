module Orders

	def orders_init
		@orders = []
	end

	private

	def sort_orders
		$logger.info "Sorting orders"

		# Nearest orders first
		@orders.sort! do |a,b|
			# Food goes before rest
			if a.order != :FORAGE and b.order == :FORAGE
				1
			elsif a.order == :FORAGE and b.order != :FORAGE
				-1	
			elsif a.order != :FORAGE and b.order != :FORAGE
				# Raze before harvest
				if a.order == :RAZE
					-1
				elsif b.order == :RAZE
					1	
				else
					0
				end
			else
				# Nearest food first
				adist = Distance.new( self.pos, a.square)
				bdist = Distance.new( self.pos, b.square)

				adist.dist <=> bdist.dist
			end
		end
	end

	public

	#
	# Returns true if order added, false otherwise
	# 
	def set_order square, what, offset = nil
		n = Order.new(square, what, offset)

		square = ai.map[n.square.row][ n.square.col ]
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
			# order already present
			return false if o == n
		end

		$logger.info { "Setting order #{ what } on square #{ square.to_s } for #{ self.to_s }" }

		if $region
			liaison  = $region.path_direction self.square, square
			if liaison.nil?
				str = "No path to target #{ square } for #{ self.to_s }; "
				if what == :ASSEMBLE #or what == :HARVEST
					str << "doing our best"
					$logger.info str
				else
					str << "ignoring order"
					$logger.info str
					return false
				end
			end
		end

		# ASSEMBLE overrides the rest of the orders
		clear_orders if what == :ASSEMBLE

		# Reset all liaisons of current orders, otherwise 
		# the ant may possibly move in a wrong direction if
		# new order is cleared
		@orders.each { |o| o.clear_liaison }

		@orders.insert 0,n

if false
		if $region and not false === liaison 
			$logger.info { "Setting order LIAISON on square #{ liaison } for #{ self.to_s }" }
			@orders.insert 0, Order.new( liaison, :LIAISON )

			# Don't sort for liaison
		else
			sort_orders
		end
else
		sort_orders
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

		#evade_reset
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
		end
	end

	def orders?
		@orders.size > 0
	end


	def order_distance
		return nil unless orders?

		Distance.new pos, @orders[0].square
	end


	#
	# Delete all orders aimed at specific square
	#
	def remove_target_from_order t
		if orders?
			p = nil
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
				@orders.delete p
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
		else
			$logger.info { "#{ to_s } has no order #{ order}!" }
		end
		
	end

	def handle_orders
		return false if moved?

		prev_order = (orders?) ? @orders[0].square: nil

		while orders?
			order_sq    = @orders[0].square
			order_order = @orders[0].order

			if order_order == :ATTACK
				d = Distance.new self.square, order_sq 
				if d.in_view?
					unless !ai.map[ order_sq.row][ order_sq.col].ant.nil? and
					       ai.map[ order_sq.row][ order_sq.col].ant.enemy?

						$logger.info { "Clearing attack target #{ order_sq.to_s}." }
						clear_first_order
						next
					end
				end 
			end

			if self.square == order_sq
				# Done with this order, reached the target

				#self.trail.set_trail order_sq  unless order_order == :ASSEMBLE

				if order_order == :RAZE
					$logger.info { "Hit anthill at #{ self.square.to_s }" }

					# TODO: clear_raze will move all raze targets, including
					#       possibly target of current ant. Check if following
					#		works.
					clear_first_order
					@ai.clear_raze self.square	
					
				else
					$logger.info { "#{ to_s } reached target for order #{ order_order }" }

					if order_order == :HARVEST
						# Keep the order in the list, don't remove
						return true
					else
						clear_first_order
					end
				end


				next
			end

			if order_order == :ASSEMBLE
				if !collective
					clear_first_order
					next
				end
			end

			# Check if in-range when visible for food
			if order_order == :FORAGE
				sq = order_sq
				if $region
					closest = BaseStrategy.closest_ant_region @ai.map[ sq.row][ sq.col], @ai
				else
					closest = closest_ant [ sq.row, sq.col], @ai
				end
				unless closest.nil?
					d = Distance.new closest, sq

					if d.in_view? and !@ai.map[ sq.row ][sq.col].food?
						# food is already gone. Skip order
						clear_first_order true
						next
					end
				end
			end

			# check if harvest target is water
			if order_order == :HARVEST and evading?
				sq = order_sq
				d = Distance.new self, sq

				# Use of in_danger here is not because of attack, but because
				# we want to get closer to the target square than in_view
				if d.in_danger? and @ai.map[ sq.row ][sq.col].water?
					$logger.info { "#{ self.to_s } harvest target #{ sq } is water. Can't get any closer" }
					@orders[0].offset = [ -( sq.row - self.row ), - (sq.col - self.col ) ]
					$logger.info { "Set order offset to #{ @orders[0].offset }." }
					stay
					evade_reset
					return
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
			$logger.info { "#{ to_s } moving to #{ @orders[0].square.to_s }" }
		end

		if $region
			move_to @orders[0].handle_liaison( self.square, ai )

if false
			what = @orders[0].order 
			sq = ai.map[ @orders[0].square.row ][ @orders[0].square.col ]

			if what == :LIAISON
				move_to sq 
			else
				$logger.info { "Determining new path for order #{ what }" }
				liaison  = $region.path_direction self.square, sq
				if liaison.nil?
					# Apparently, this never happens...logical, otherwise
					# there would be no order to move.
					str = "No path to target #{ sq } for #{ self.to_s }; "
					if what == :ASSEMBLE 
						str << "doing our best"
						$logger.info str
						move_to sq
					else
						str << "ignoring order"
						$logger.info str
						return false
					end
				else
					if false === liaison 
						$logger.info "no liaison needed - move directly"

						# NOTE: the liaison order is abused here somewhat.
						# The target square is in view of the current order,
						# but there is a possibility that the ant will move
						# through the same region as the liaison; this means
						# that in the next move, the path would be redetermined
						# and the ant would move to the liaison, eg. back to this
						# square. It results in twitch-behaviour.
						#
						# Setting liaison like this works fine, because of the
						# loop over orders in handle_orders(). Consecutive orders
						# with same target are reached in the same loop.
						#
						$logger.info { "Abusing order LIAISON on square #{ sq } for #{ self.to_s }" }
						@orders.insert 0, Order.new( sq, :LIAISON )
					else
						$logger.info { "Setting order LIAISON on square #{ liaison } for #{ self.to_s }" }
						@orders.insert 0, Order.new( liaison, :LIAISON )
					end
				end

				what = @orders[0].order 
				sq =  @orders[0].square
				$logger.info { "Moving to #{ sq.to_s } for order #{ what}" }
				move_to sq
end
			end
		else
			move_to sq
		end

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
	
					da = Distance.new( pos, @orders[0].square )
					de = Distance.new( e.pos, @orders[0].square )
	
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

	def find_orders what
		list = {}

		count = 0
		@orders.each do |n|
#			next if n.order == :LIAISON

			if n.order == what
				list[ n.square ] = count
			end

			count += 1
		end

		list
	end
end
