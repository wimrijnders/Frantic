
class Harvesters

	def initialize	rows, cols, viewradius2
		# Find smalles square which fits into given viewradius
		radius = 1
		while 2*(radius + 1)*(radius + 1) <= viewradius2
			radius +=1
		end
		$logger.info "Found square with radius #{ radius }"

		@dist = 2*radius + 1

		rowdim = rows/@dist
		rowdim += 1 unless rows % @dist == 0
		coldim = cols/@dist
		coldim += 1 unless cols % @dist == 0

		@arr = Array.new( rowdim ) do |row|
			row = Array.new coldim 
		end
	end


	def to_s
		"Harvesters (rows, cols, dist) = ( #{ @arr.length }, #{ @arr[0].length }, #{ @dist } )"
	end


	def move_line_right r,c, rel
		return if rel[1] == 0

		rrel = rel[0]
		rnorm = norm_r( r + rrel ) 
		( rel[1] -1).downto( 0 ) do |crel|
			cnorm = norm_c( c + crel)
	
			thisant = @arr[ rnorm][ cnorm ]
			thisant.change_order thisant.ai.map[ rnorm*@dist][ norm_c(cnorm + 1) *@dist], :HARVEST
			@arr[ rnorm][ norm_c(cnorm + 1) ] = @arr[ rnorm][ cnorm ]
			@arr[ rnorm][ cnorm ] = nil
		end
	end

	def move_line_left r,c, rel
		return if rel[1] == 0

		rrel = rel[0]
		rnorm = norm_r( r + rrel ) 
		( rel[1] +1).upto( 0 ) do |crel|
			cnorm = norm_c( c + crel)
	
			thisant = @arr[ rnorm][ cnorm ]
			thisant.change_order thisant.ai.map[ rnorm*@dist][ norm_c(cnorm - 1) *@dist], :HARVEST
			@arr[ rnorm][ norm_c(cnorm - 1) ] = @arr[ rnorm][ cnorm ]
			@arr[ rnorm][ cnorm ] = nil
		end
	end

	def move_line_up r,c, rel
		return if rel[0] == 0

		crel = rel[1]
		cnorm = norm_c( c + crel ) 
		( rel[0] + 1 ).upto(0) do |rrel|
			rnorm = norm_r( r + rrel)

			thisant = @arr[ rnorm][ cnorm ]
			thisant.change_order thisant.ai.map[ norm_r(rnorm -1)*@dist][ cnorm*@dist], :HARVEST
			@arr[ norm_r( rnorm -1) ][ cnorm ] = @arr[ rnorm][ cnorm ]
			@arr[ rnorm][ cnorm ] = nil
		end
	end

	def move_line_down r,c, rel
		return if rel[0] == 0

		crel = rel[1]
		cnorm = norm_c( c + crel ) 
		( rel[0] -1 ).downto(0) do |rrel|
			rnorm = norm_r( r + rrel)

			thisant = @arr[ rnorm][ cnorm ]
			thisant.change_order thisant.ai.map[ norm_r(rnorm +1)*@dist][ cnorm*@dist], :HARVEST
			@arr[ norm_r( rnorm +1) ][ cnorm ] = @arr[ rnorm][ cnorm ]
			@arr[ rnorm][ cnorm ] = nil
		end
	end

	def move_lines ant, r, c, rel
		# Determine quadrant
		if rel[0] < 0 and rel[1] >= 0
			$logger.info "quadrant topright"
			move_line_right r,c, rel
			move_line_up r,c, [ rel[0], 0 ]
		elsif rel[0] >= 0 and rel[1] > 0
			$logger.info "quadrant bottomright"

			move_line_down r,c, rel
			move_line_right r,c, [0, rel[1] ]
		elsif rel[0] > 0 and rel[1] <= 0
			$logger.info "quadrant bottomleft"
			move_line_left r,c, rel
			move_line_down r,c, [ rel[0], 0 ]
		elsif rel[0] <= 0 and rel[1] < 0
			$logger.info "quadrant topleft"
			move_line_up r,c, rel
			move_line_left r,c, [0, rel[1] ]
		end

		# Finally, move the new recruit to the nearest place
		ant.set_order ant.ai.map[ r*@dist][ c*@dist], :HARVEST
		@arr[r][c] = ant
	end

	def enlist ant
		# Find nearest location in harvesters grid for given ant
		r = norm_r (ant.row*1.0/@dist).round
		c = norm_c (ant.col*1.0/@dist).round

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
				move_lines ant, r, c, rel

				#rcoord = norm_r( r + rel[0])
				#ccoord = norm_c( c + rel[1])
				#ant.set_order ant.ai.map[ rcoord*@dist ][ ccoord*@dist ], :HARVEST
				#@arr[rcoord][ccoord] = ant
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

	def rows
		@arr.length
	end

	def cols
		@arr[0].length
	end

	def norm_r r
		(r + rows ) % rows 
	end

	def norm_c c
		(c  + cols ) % cols 
	end


	def check_spot r,c, roffs, coffs
		rrel = norm_r( r + roffs )
		crel = norm_c( c + coffs )

		if @arr[ rrel ][ crel ].nil?
			# Found a spot
			# return relative position
			throw:done, [ roffs, coffs ]
		end
	end


	#
	# Find the closest empty position for a new recruit
	#
	def find_location r,c
		offset = nil
		radius = 1

		offset = catch :done do	

			# TODO: fix this loop to end when entire array has been searched
			diameter = 2*radius + 1
			while diameter <= rows or diameter <= cols 
	
				# Start from 12 o'clock and move clockwise

				0.upto(radius) do |n|
					check_spot r, c, -radius, n
				end if diameter <= cols

				(-radius+1).upto(radius).each do |n|
					check_spot r, c, n, radius
				end if diameter <= rows

				( radius -1).downto( -radius ) do |n|
					check_spot r, c, radius, n
				end if diameter <= cols

				( radius - 1).downto( -radius ) do |n|
					check_spot r, c, n, -radius
				end if diameter <= rows

				( -radius + 1).upto( -1 ) do |n|
					check_spot r, c, -radius, n
				end if diameter <= cols

				# End loop
				radius += 1
				diameter = 2*radius + 1
			end
		end

		offset
	end
end
