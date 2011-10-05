class Region
	
	@@counter = 0

	def initialize viewradius2
		@liaison = {}

		# make the radius template

		# determine max size
		dim = Math.sqrt( viewradius2 ).ceil
		@template = Array.new( dim ) do |row|
			row = Array.new(dim)
		end

		(0...dim).each do |x|
			(0...dim).each do |y|
				in_radius = ( x*x + y*y) <= viewradius2
				@template[x][y] = in_radius
			end
		end

	end

	def to_s
		str = ""
		dim = @template.length
		(1...dim).each do |x|
			(0...dim).each do |y|
				str << (@template[x][y]? "x" : ".")
			end
			str << "\n"
		end
		str
	end

	def show_regions square
		str = "\n"
		dim = @template.length
		((-dim+1)...dim).each do |row|
			((-dim+1)...dim).each do |col|
				sq = square.rel [ row, col ]

				if sq.region
					if sq.region < 10
						r = "0" + sq.region.to_s
					else
						r = sq.region.to_s
					end
					str << r 
				else
					str << ".."	
				end
			end
			str << "\n"
		end
		str
	end

	def set_region square, x, y
		sq = square.rel [ x, y ]
		if !sq.region
			return if sq.water?
			return if sq.region

			# If no region present, fill one in
			# Check neighbor regions, and select that if present	
			regions = neighbor_regions sq
			if regions.length > 0
				regions.each_key do |region|
					unless sq.region
						# First region we encounter, we use for current square
						sq.region = region
					else
						# For the rest, we are liaison
	

						# Two keys, because we can go in both ways via 
						# liasion square
						key1 = sq.region.to_s + "_" +    region.to_s
						key2 =    region.to_s + "_" + sq.region.to_s

						# Don't overwrite previous liaisons
						next if @liaison[ key1 ]

						@liaison[ key1 ] = sq
						@liaison[ key2 ] = sq

						$logger.info "#{ sq.to_s } liaison for #{ key1 }."
					end
				end
			else 
				# No neighbors, fill in a new region
				sq.region = @@counter
				@@counter += 1
			end
		end
	end

	def quadrant
		dim = @template.length
		(1...dim).each do |x|
			(0...dim).each do |y|
				next unless @template[x][y]
				yield x, y
			end
		end
	end

	def find_regions square
		$logger.info "find_regions for #{ square }"

		dim = @template.length
		quadrant {|x,y| set_region square, -x,  y }
		quadrant {|x,y| set_region square,  y,  x }
		quadrant {|x,y| set_region square,  x, -y }
		quadrant {|x,y| set_region square, -y, -x }

		$logger.info show_regions square
	end


	def neighbor_regions sq
		ret = {}

		[ :N, :E, :S, :W ].each do |dir|
			ret[ sq.neighbor( dir ).region ] = true if sq.neighbor( dir).region
		end

		ret
	end
end
