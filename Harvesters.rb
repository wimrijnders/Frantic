
class Harvesters

	def initialize	rows, cols, viewradius2
		# Find smalles square which fits into given viewradius
		radius = 1
		while 2*(radius + 1)*(radius + 1) <= viewradius2
			radius +=1
		end
		$logger.info "Found square with radius #{ radius }"

		@dist = 2*radius + 1

		@arr = Array.new( rows/@dist ) do |row|
			row = Array.new cols/@dist
		end
	end


	def to_s
		"Harvesters (rows, cols, dist) = ( #{ @arr.length },#{ @arr[0].length }, #{ @dist } )"
	end

	def enlist ant
		# Find nearest location in harvesters grid for given ant
		r = (ant.row*1.0/@dist).round
		c = (ant.col*1.0/@dist).round

		$logger.info "Setting #{ ant.to_s } to a spot at ( #{ r}, #{c} )"
		if @arr[r][c].nil?
			$logger.info "Found #{ ant.to_s } a spot at ( #{ r}, #{c} )"
			ant.set_order ant.ai.map[ r*@dist][ c*@dist], :HARVEST
			@arr[r][c] = ant
		else
			$logger.info "Harvester spot ( #{ r}, #{c} ) occupied."
			rel = find_location r,c

			unless rel.nil?
				$logger.info "Relative location( #{ rel[0] }, #{ rel[1] } ) is unoccupied."
				# Determine quadrant
				if rel[0] < 0 and rel[1] >= 0
					# quadrant topright
					rrel = rel[0]
					rnorm = norm_r( r + rrel ) 
					( rel[1] -1).downto( 0 ) do |crel|
						cnorm = norm_c( c + crel)
			
						ant.set_order ant.ai.map[ rnorm*@dist][ norm_c(cnorm + 1) *@dist], :HARVEST
						@arr[ rnorm][ norm_c(cnorm + 1) ] = @arr[ rnorm][ cnorm ]
						@arr[ rnorm][ cnorm ] = nil
					end

					crel = rel[1]
					cnorm = norm_c( c + crel ) 
					( rel[0] + 1 ).upto(0) do |rrel|
						rnorm = norm_r( r + rrel)

						ant.set_order ant.ai.map[ norm_r(rnorm -1)*@dist][ cnorm*@dist], :HARVEST
						@arr[ norm_r( rnorm -1) ][ cnorm ] = @arr[ rnorm][ cnorm ]
						@arr[ rnorm][ cnorm ] = nil
					end

					# Finally, move the new recruit to the nearest place
					ant.set_order ant.ai.map[ r*@dist][ c*@dist], :HARVEST
					@arr[r][c] = ant
				elsif rel[0] >= 0 and rel[1] > 0
					# quadrant bottomright

					crel = rel[1]
					cnorm = norm_c( c + crel ) 
					( rel[0] -1 ).upto(0) do |rrel|
						rnorm = norm_r( r + rrel)

						ant.set_order ant.ai.map[ norm_r(rnorm +1)*@dist][ cnorm*@dist], :HARVEST
						@arr[ norm_r( rnorm +1) ][ cnorm ] = @arr[ rnorm][ cnorm ]
						@arr[ rnorm][ cnorm ] = nil
					end

					rrel = rel[0]
					rnorm = norm_r( r + rrel ) 
					( rel[1] -1).downto( 0 ) do |crel|
						cnorm = norm_c( c + crel)
			
						ant.set_order ant.ai.map[ rnorm*@dist][ norm_c(cnorm + 1) *@dist], :HARVEST
						@arr[ rnorm][ norm_c(cnorm + 1) ] = @arr[ rnorm][ cnorm ]
						@arr[ rnorm][ cnorm ] = nil
					end

					# Finally, move the new recruit to the nearest place
					ant.set_order ant.ai.map[ r*@dist][ c*@dist], :HARVEST
					@arr[r][c] = ant
				elsif rel[0] > 0 and rel[1] <= 0
					# quadrant bottomleft

					crel = rel[1]
					cnorm = norm_c( c + crel ) 
					( rel[0] -1 ).upto(0) do |rrel|
						rnorm = norm_r( r + rrel)

						ant.set_order ant.ai.map[ norm_r(rnorm +1)*@dist][ cnorm*@dist], :HARVEST
						@arr[ norm_r( rnorm +1) ][ cnorm ] = @arr[ rnorm][ cnorm ]
						@arr[ rnorm][ cnorm ] = nil
					end

					rrel = rel[0]
					rnorm = norm_r( r + rrel ) 
					( rel[1] +1).upto( 0 ) do |crel|
						cnorm = norm_c( c + crel)
			
						ant.set_order ant.ai.map[ rnorm*@dist][ norm_c(cnorm - 1) *@dist], :HARVEST
						@arr[ rnorm][ norm_c(cnorm - 1) ] = @arr[ rnorm][ cnorm ]
						@arr[ rnorm][ cnorm ] = nil
					end

					# Finally, move the new recruit to the nearest place
					ant.set_order ant.ai.map[ r*@dist][ c*@dist], :HARVEST
					@arr[r][c] = ant
				elsif rel[0] <= 0 and rel[1] < 0
					# quadrant topleft
					rrel = rel[0]
					rnorm = norm_r( r + rrel ) 
					( rel[1] +1).upto( 0 ) do |crel|
						cnorm = norm_c( c + crel)
			
						ant.set_order ant.ai.map[ rnorm*@dist][ norm_c(cnorm - 1) *@dist], :HARVEST
						@arr[ rnorm][ norm_c(cnorm - 1) ] = @arr[ rnorm][ cnorm ]
						@arr[ rnorm][ cnorm ] = nil
					end

					crel = rel[1]
					cnorm = norm_c( c + crel ) 
					( rel[0] + 1 ).upto(0) do |rrel|
						rnorm = norm_r( r + rrel)

						ant.set_order ant.ai.map[ norm_r(rnorm -1)*@dist][ cnorm*@dist], :HARVEST
						@arr[ norm_r( rnorm -1) ][ cnorm ] = @arr[ rnorm][ cnorm ]
						@arr[ rnorm][ cnorm ] = nil
					end

					# Finally, move the new recruit to the nearest place
					ant.set_order ant.ai.map[ r*@dist][ c*@dist], :HARVEST
					@arr[r][c] = ant
				end
			end
		end
	end

	def remove ant
		o = ant.find_order :HARVEST
		if o 
			$logger.info "Removing ant #{ ant.to_s } from harvesters."
			@arr[ o.square.row/@dist ][ o.square.col/@dist ] = nil 
		else
			$logger.info "Ant #{ ant.to_s } was not harvester."
		end
	end

	def norm_r r
		(r + @arr.length ) % @arr.length
	end

	def norm_c c
		(c  + @arr[0].length ) % @arr[0].length
	end

	#
	# Find the closest empty position for a new recruit
	def find_location r,c
		radius = 1

		# TODO: fix this loop to end when entire array has been searched
		while true
			# Start from 12 o'clock and move clockwise
			0.upto(radius) do |n|
				rrel = norm_r( r - radius )
				crel = norm_c( c + n )
	
				if @arr[ rrel ][ crel ].nil?
					# Found a spot
					# return relative position
					return [ -radius, n ]
				end
			end
			(-radius+1).upto(radius).each do |n|
				rrel = norm_r( r +n )
				crel = norm_c( c + radius )
	
				if @arr[ rrel ][ crel ].nil?
					# Found a spot
					# return relative position
					return [ n, radius ]
				end
			end
			( radius -1).downto( -radius ) do |n|
				rrel = norm_r( r + radius )
				crel = norm_c( c + n )

				if @arr[ rrel ][ crel ].nil?
					# Found a spot
					# return relative position
					return [ radius, n ]
				end
			end
			( radius - 1).downto( -radius ) do |n|
				rrel = norm_r( r + n )
				crel = norm_c( c -radius )

				if @arr[ rrel ][ crel ].nil?
					# Found a spot
					# return relative position
					return [ n, -radius ]
				end
			end
			( -radius + 1).upto( -1 ) do |n|
				rrel = norm_r( r - radius )
				crel = norm_c( c + n )
	
				if @arr[ rrel ][ crel ].nil?
					# Found a spot
					# return relative position
					return [ -radius, n ]
				end
			end

			# End loop
			radius += 1
		end

		nil
	end
end
