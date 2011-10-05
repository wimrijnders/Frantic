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

	def set_order square, what, offset = nil
		n = Order.new(square, what, offset)

		@orders.each do |o|
			# order already present
			return if o == n
		end

		$logger.info "Setting order #{ what } on square #{ square.to_s } for #{ self.to_s }"

		# ASSEMBLE overrides the rest of the orders
		clear_orders if what == :ASSEMBLE

		@orders << n

		sort_orders
	end


	def clear_orders
		p = find_order :HARVEST
		if p
			ai.harvesters.remove self if ai.harvesters
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
			$logger.info "Clearing order #{ order } for #{ self.to_s }."
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
					#$logger.info("Found p")
					break
				end
			end

			unless p.nil?
				@orders.delete p
				ai.harvesters.remove self if ai.harvesters and p.order == :HARVEST
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
					#$logger.info("Found p")
					break
				end
			end
		end

		p	
	end


	def change_order sq, order
		p = find_order order

		if p
			$logger.info "Change order #{ order } to square #{ sq.to_s } for #{ self.to_s }"
			p.square = sq
			p.offset = nil	if order == :HARVEST
		else
			$logger.info "#{ to_s } has no order #{ order}!"
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

						$logger.info "Clearing attack target #{ order_sq.to_s}."
						@orders = @orders[1..-1]
						next
					end
				end 
			end

			if self.square == order_sq
				# Done with this order, reached the target

				#self.trail.set_trail order_sq  unless order_order == :ASSEMBLE

				if order_order == :RAZE
					$logger.info "Hit anthill at #{ self.square.to_s }"

					# TODO: clear_raze will move all raze targets, including
					#       possibly target of current ant. Check if following
					#		works.
					@orders = @orders[1..-1]
					@ai.clear_raze self.square	
					
				else
					$logger.info "#{ to_s } reached target for order #{ order_order }"

					if order_order == :HARVEST
						# Keep the order in the list, don't remove
						return true
					else
						@orders = @orders[1..-1] 
					end
				end


				next
			end

			if order_order == :ASSEMBLE
				if !collective
					@orders = @orders[1..-1]
					next
				end
			end

			# Check if in-range when visible for food
			if order_order == :FORAGE
				sq = order_sq
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

			# check if harvest target is water
			if order_order == :HARVEST and evading?
				sq = order_sq
				d = Distance.new self, sq

				# Use of in_danger here is not because of attack, but because
				# we want to get closer to the target square than in_view
				if d.in_danger? and @ai.map[ sq.row ][sq.col].water?
					$logger.info "#{ self.to_s } harvest target #{ sq } is water. Can't get any closer"
					@orders[0].offset = [ -( sq.row - self.row ), - (sq.col - self.col ) ]
					$logger.info "Set order offset to #{ @orders[0].offset }."
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
			$logger.info "#{ to_s } moving to #{ @orders[0].square.to_s }"
		end
		move_to @orders[0].square

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
						$logger.info "check_orders #{ to_s } skipping."
						@orders = @orders[1..-1]
					else
						# We can still make it first! Even if we die...
						$logger.info "check_orders #{ to_s } we can make it!"
						throw :done
					end
				end
			end
		end

		orders?
	end
end
