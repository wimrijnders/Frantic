
## WRI TRY
class Pathinfo
	@@region = nil

	def self.set_region region
		@@region = region
	end

	def initialize from, to, path = nil
		@from, @to = from, to

		if path
			@path = path
		else
			path = $region.find_path from, to

			@path = path if path
		end

		@distance = calc_distance if @path
	end

	def calc_distance
		prev = @from
		total = 0
		0.upto(@path.length-2) do |n|
			cur = @@region.get_liaison @path[n], @path[n+1]
			dist = Distance.new prev, cur
			total += dist.dist

			prev = cur
		end

		# add the final distance to the target point
		dist = Distance.new prev, @to
		total += dist.dist

		$logger.info "Distance #{ @from.to_s }-#{ @to.to_s } through #{ @path.length() -1 } liasions: #{ total }."

		total
	end

	def path?
		!@path.nil?
	end

	def dist
		@distance
	end
end


class Region
	
	@@counter = 0
	@@ai = nil

	def initialize ai
		@ai = ai
		@liaison = {}
		@paths = {}
		@non_paths = {}

		# make the radius template

		# determine max size
		dim = Math.sqrt( ai.viewradius2 ).ceil
		@template = Array.new( dim ) do |row|
			row = Array.new(dim)
		end

		(0...dim).each do |x|
			(0...dim).each do |y|
				in_radius = ( x*x + y*y) <= ai.viewradius2
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

	private

	def set_liaison from, to, square
		# Don't overwrite existing liaison
		unless get_liaison from, to
			unless @liaison[ from ]
				@liaison[from] = { to => square }
			else
				@liaison[from][ to ] = square
			end
			$logger.info "#{ square } liaison for #{ from }-#{ to }."
		end
	end

	public

	def get_liaison from, to
		if @liaison[ from ]
			@liaison[from][to]
		else
			nil
		end
	end

	private

	def set_non_path from, to
		unless @non_paths[ from ]
			@non_paths[from] = { to => true }
		else
			@non_paths[from][ to ] = true
		end
	end

	def get_non_path from, to
		if @non_paths[ from ]
			@non_paths[from][to]
		else
			false
		end
	end

	def clear_non_paths
		@non_paths = {}
	end


	def set_path from, to, value
		# Don't overwrite existing paths
		unless get_path from, to
			unless @paths[ from ]
				@paths[from] = { to => value }
			else
				@paths[from][ to ] = value
			end

			$logger.info "Added new path #{ from }-#{ to }: #{ value }"
		end
	end


	def get_path from, to
		if @paths[ from ]
			@paths[from][to]
		else
			nil
		end
	end


	def all_paths
		# Iterating over array, so that any paths
		# added during the loop will not be iterated over
		@paths.keys.each do |from|
			@paths.keys.each do |to|
				value = @paths[from][to]
				yield from, to , value	unless value.nil?
			end
		end
	end


	#
	#
	#
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
						from = sq.region
						to   = region
	
						set_liaison from, to, sq
						set_liaison to, from , sq

						# New liaisons added; need to retest for new possible paths
						clear_non_paths


						path = [ from, to]
						set_path from, to, path 
						set_path to, from, path.reverse 
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


	def neighbor_regions sq
		ret = {}

		[ :N, :E, :S, :W ].each do |dir|
			ret[ sq.neighbor( dir ).region ] = true if sq.neighbor( dir).region
		end

		ret
	end

	def search_liaison from, to, current_path
		$logger.info "search_liaison searching #{ from }-#{ to }: #{ current_path }"
		cur = @liaison[from]

		if cur
			if cur[ to ]
				throw :done, current_path + [to]
			end

			cur.each_key do |key|
				unless current_path.include? key
					search_liaison key, to, current_path + [key]
				end
			end
		end

		nil
	end

	public

	def show_paths	paths
		str = ""

		all_paths each do |from, to, value|
			str << "...#{from}-#{to}: " + paths[key].join( ", ") + "\n"
		end

		str
	end


	def find_regions square
		return if square.done_region

		$logger.info "find_regions for #{ square }"

		dim = @template.length
		quadrant {|x,y| set_region square, -x,  y }
		quadrant {|x,y| set_region square,  y,  x }
		quadrant {|x,y| set_region square,  x, -y }
		quadrant {|x,y| set_region square, -y, -x }

		square.done_region = true
		$logger.info show_regions square
	end


	def find_path from, to
		# Assuming input are squares
		from_r = from.region
		to_r   = to.region

		# Test for unknown regions
		return nil unless from_r and to_r

		# Test same region
		return [] if from_r == to_r

		$logger.info "finding path from #{ from.to_s } to #{ to.to_s}; regions #{ from_r}-#{to_r }"

		result = get_path from_r, to_r
		if result
			$logger.info "found cached result #{ result }."
			return result
		end
		if get_non_path from_r, to_r
			$logger.info "found cached non-result for #{ from_r }-#{to_r}."
			return nil
		end
			
	
		result = catch :done do
			search_liaison from_r, to_r, [from_r]
		end

		if result
			$logger.info "search_liaison path found for #{ from_r } to #{ to_r }: #{ result }"
			# Cache the result
			set_path from_r, to_r, result
			set_path to_r, from_r, result.reverse
		else
			$logger.info "search_liaison no path found for #{ from_r } to #{ to_r }"
			set_non_path from_r, to_r
			set_non_path to_r, from_r
		end

		result
	end
end
