
class Pathinfo

	@@region = nil

	def self.set_region region
		@@region = region
	end

	def initialize from, to, path = nil
		@from, @to = from, to

		unless path
			path = $region.find_path from, to
			@path_dist = Pathinfo.path_distance path
		else
			@path = path
			@path_dist = Pathinfo.path_distance path, false
		end
		@distance = calc_distance

		self
	end


	def self.path_distance path, check_cache = true
		return 0 if path.length <= 2
		$logger.info "entered"

		if check_cache 
				# Consult the cache first
			item = $region.get_path_basic path[0], path[-1]
			unless item.nil?
				return item[:dist]
			end

			# Not in cache; do the calculation
			$logger.info "path not in cache"
		end

		prev = nil
		total = 0
		0.upto(path.length-2) do |n|
			cur = @@region.get_liaison path[n], path[n+1]

			unless prev.nil?
				dist = Distance.get prev, cur
				total += dist.dist
			end

			prev = cur
		end

		# Perhaps TODO: store value into cache
		#               In that case, consult all other places where distance
		#               is calculated and stored to cache

		#$logger.info {
		#	path_length = path.length() - 1
		#	"Distance path #{ path } through #{ path_length } liasions: #{ total }." 
		#}

		total
	end

	def self.total_path_distance from, to, path, path_dist = nil
		total = 0
		if path.nil? or path.length < 2
			# There is no path; calculate distance between from and to
			dist = Distance.get from, to
			total += dist.dist
		else
			if path_dist.nil?
				path_dist = Pathinfo.path_distance path, false
			end

			cur = @@region.get_liaison path[0], path[1]
			dist = Distance.get from, cur
			total += dist.dist

			cur = @@region.get_liaison path[-2], path[-1]
			dist = Distance.get cur, to
			total += dist.dist

			total += path_dist
		end

		#$logger.info {
		#	path_length = path.length() - 1
		#	path_length = 0 if path_length < 0
		#	"Distance #{ from.to_s }-#{ to.to_s } through #{ path_length } liasions: #{ total }." 
		#}

		total
	end

	def calc_distance
		Pathinfo.total_path_distance @from, @to, @path, @path_dist
	end

	def path?
		!@path.nil?
	end

	def path
		@path
	end

	def path_dist
		@path_dist
	end

	def dist
		@distance
	end
end



class LiaisonSearch

	NO_MAX_LENGTH      = -1
	DEFAULT_MAX_LENGTH = 15
	MAX_COUNT          = 8000

	def initialize cache, find_shortest = false, max_length = nil
		@liaison = cache
		@find_shortest = find_shortest
		@cached_results = {}
		@count = 0

		if max_length.nil?
			@max_length = DEFAULT_MAX_LENGTH
		else
			@max_length = max_length 

			$logger.info {
				str = "Doing search with "
				if max_length == NO_MAX_LENGTH
					str << "unlimited depth"
				else
					str << "depth #{ max_length }"
				end

				str
			}
		end
	end


	def search from_r, to_list_r
		$logger.info "entered #{ from_r }-#{ to_list_r }"
		if from_r.nil?
			$logger.info "from_r empty, not searching"
			return
		end

		to_list_r.compact!

		# Shouldn't be necessary, since all searches passed are unknown
		# Keeping it in as a safeguard
		# TODO: check if can be removed.
		to_list_r.clone.each do |r|
			if $region.get_path_basic from_r, r
				$logger.info { "#{ from_r }-#{ r } already in cache; skipping." }
				to_list_r.delete r
			end 
			Fiber.yield
		end

		if to_list_r.length == 0
			$logger.info "to_list_r empty, not searching."
			return
		end

		@cur_best_dist = nil;

		if to_list_r.length == 1 and not @find_shortest
			$logger.info "Only one item in to_list_r; forcing find_shortest"
			@find_shortest = true
		end

		$logger.info "searching shortest path" if @find_shortest

		if @find_shortest and to_list_r.include? from_r 
			# Same region always wins
			$logger.info { "found same region" }
			return [ [] ]
		end


		@search_list = [ [ from_r, to_list_r, [from_r] ] ]
		@search_results = []
		catch :done do 
			while item = @search_list.shift

				search_liaisons item[0], item[1], item[2] 
		
				# Be cooperative with the other fibers
				Fiber.yield
			end
		end


		result = @search_results
		if @find_shortest and not result.nil? and result.length > 0
			# Shortest item is last in list.
			result = [ result[-1] ]
		end

		result
	end


	private

	def search_liaisons from, to_list, current_path
		to_list.compact!
		return nil if to_list.length == 0

		if @count >= MAX_COUNT
			$logger.info { "Count #{ @count } hit the max; aborting this search." }
			throw :done
		else
			@count +=1
		end
	
		# Safeguard to avoid too deep searches
		if @max_length != NO_MAX_LENGTH and current_path.length >= @max_length 
			$logger.info { "Path length >= #{ @max_length }; skipping" }
			return
		end

		if @find_shortest and not @cur_best_dist.nil?
			dist = Pathinfo.path_distance current_path

			if dist > @cur_best_dist
				$logger.info { "cur dist #{ dist } > cur best #{ @cur_best_dist}; skipping" }
				return
			end
			Fiber.yield
		end



		$logger.info { "searching #{ from }-#{ to_list }: #{ current_path }" }
		results = []
		found_to = []

		known_results = to_list & @cached_results.keys
		if known_results.length > 0
			$logger.info { "Already found results for targets #{ known_results}. Not searching these further." }
			to_list -= @cached_results.keys

			if to_list.length == 0
				$logger.info "to_list now empty. Not searching further."
				return
			end
		end

		cur = @liaison[from]
		if cur
			$logger.info { "#{ cur.length } targets from liaison #{ from }" }

			to_list.each do |to|
				if cur[ to ]
					result = current_path + [to]
					$logger.info { "found path #{ from }-#{ to_list }: #{ result }" }

					if @find_shortest
						dist = Pathinfo.path_distance result

						if @cur_best_dist.nil? or dist < @cur_best_dist
							$logger.info { "path is new shortest" }
							@cur_best_dist = dist
							results << result 
							@cached_results[to] = result
						else
							next
						end
						Fiber.yield
					else
						results << result 
						@cached_results[to] = result
					end

					found_to << to
				end
			end

			@search_results += results

			if @find_shortest and results.length > 0 
				# No point in looking further, any further paths will be longer
				return
			end

			to_list -= found_to

			cur.keys.each do |key|
				# Condition to prevent loops in path
				unless current_path.include? key
					tmp_path = current_path + [key]
		
					# Add to cache
					Region.add_paths [ tmp_path ] 

					@search_list << [ key, to_list, tmp_path ]
				end
			end
		else
			# Should never happen; there is always the way back for any given liaison
			$logger.info { "WARNING: No targets from liaison #{ from }" }
		end
	end
end


class Region
	
	@@counter = 0
	@@ai = nil

	@@add_paths = []
	@@done_paths = {}
	@@add_regions = []

	private 

	def self.add_paths result
		$logger.info { "add_paths #{ result }" }

		result.clone.each do |path|
			if @@done_paths[ path ]
				$logger.info { "path already queued" }
				result.delete path
			else
				@@done_paths[ path ] = true
			end
if false
			item = $region.get_path_basic path[0], path[-1]
			unless item.nil?
				$logger.info { "path item already there" }

				if item[:path] == path
					$logger.info { "path is the same; not adding to queue" }
					result.delete path
					next
				end
			end
end
		end



		@@add_paths.concat result
	end

	public 

	def init_fibers
		[
			Fiber1.new( self, @@add_paths ), 
			RegionsFiber.new( self, @@add_regions )
		]
	end


	def self.add_searches from, to_list, do_shortest = false, max_length = nil
		SelectSearch.add_list [ from, to_list, do_shortest, max_length ]
	end

	def self.add_regions source
		return if source.done_region

		$logger.info { "Adding region search for #{ source }" }
		@@add_regions << source 
	end


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

	#
	# Return relative offsets for a given square, for all the
	# points that are within the template.
	#
	def all_region
		dim = @template.length
		(1...dim).each do |x|
			Fiber.yield

			(0...dim).each do |y|
				if @template[x][y]
					yield x, y 
					yield y, -x 
					yield -x, -y 
					yield -y, x 
				end
			end
		end
	end

	def show_regions square
		str = "\n"
		dim = @template.length
		((-dim+1)...dim).each do |row|
			((-dim+1)...dim).each do |col|
				sq = square.rel [ row, col ]

				if sq.region
					region = sq.region % 1000

					if region < 10
						r = "__" + region.to_s
					elsif region < 100
						r = "_" + region.to_s
					else
						r = region.to_s
					end
					str << r 
				else
					str << "..."	
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

			#$mutex.synchronize do
				unless @liaison[ from ]
					@liaison[from] = { to => square }
				else
					@liaison[from][ to ] = square
				end
			#end
			$logger.info { "#{ square } liaison for #{ from }-#{ to }." }

			set_path [ from, to ]

			# New liaisons added; need to retest for new possible paths
			clear_non_paths
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

	def get_liaisons from
		@liaison[ from ]
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

	def clear_non_path from, to
		if @non_paths[ from ] and @non_paths[from][to]
			@non_paths[from].delete to
			$logger.info "cleared #{ from }-#{ to }"
		end
	end


	def set_path_basic from, to, path, dist = nil
		$logger.info "entered path: #{ path }"
		ret = :new


		# path already present?
		prev_item = get_path_basic from, to 
		unless prev_item.nil?
			# Check if newer item better

			prev_path = prev_item[ :path ]
			prev_dist = prev_item[ :dist ]

			# Path between adjacent regions always wins
			return :known if prev_path.length == 2

			# Skip if these are the same solutions
			return :known if path == prev_path

			$logger.info { "previous path: #{ prev_path }" }

			if dist.nil?
				dist = Pathinfo.path_distance path, false
			end

			if dist < prev_dist
				$logger.info { "Found shorter path for #{ from }-#{ to }: #{ path }; prev_dist: #{ prev_dist }, new_dist: #{ dist }" }
				ret = :replaced
				
			else
				$logger.info { "Path for #{ from }-#{ to } longer or equal: prev_dist: #{ prev_dist }, new_dist: #{ dist }" }
				return :known
			end
		end


		if prev_item.nil?
			if dist.nil?
				dist = Pathinfo.path_distance path, false
			end

			item = {
				:path => path,
				:dist => dist
			}

			unless @paths[ from ]
				@paths[from] = { to => item }
			else
				@paths[from][ to ] = item
			end
			clear_non_path from, to
		else
			# Replace contents of previous item
			# Changed paths are detected in pointcache, because there path
			# length are stored in the cache items. Changes in path length
			# are detected and trigger a recalculation of the pointcache item.
			prev_item[ :path] = path
			prev_item[ :dist] = dist
		end

		ret
	end

public

	def set_path path
		return [0,0,0] if path.length < 2

		$logger.info "entered path: #{ path }"
		new_count = 0
		known_count = 0
		replaced_count = 0

		from = path[0]
		to   = path[-1]

		case set_path_basic from, to, path 
		when :new
			new_count += 1
		when :known
			# This path was known; so all sub-paths are also known.
			# No need to check these
			$logger.info "path is known"
			known_count += 1
			return [ new_count, known_count, replaced_count ]
		when :replaced
			replaced_count += 1
		end


		Fiber.yield if not Fiber.current.nil?

		new1, known1, replaced1  = set_path path[0..-2]
		new_count      += new1
		known_count    += known1
		replaced_count +=  replaced1


		new1, known1, replaced1  = set_path path[1..-1]
		new_count      += new1
		known_count    += known1
		replaced_count +=  replaced1

		#$logger.info { "path #{ path }: added #{ new_count }, known #{ known_count}" }
		[ new_count, known_count, replaced_count ]
	end



	#
	# Read given item from the cache.
	#
	# If found, returns hash: { :path => path, :dist => path_length }
	# If not found, return nil
	#
	def get_path_basic from, to
		return nil if from.nil? or to.nil?

		if @paths[ from ]
			@paths[from][to]
		else
			nil
		end
	end

private

	def get_path from, to
		path = get_path_basic from, to
		if path.nil?
			nil
		else
			path[:path]
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
	# Define square sq as liaison between its own region
	# and the given region
	#
	def assign_liaison sq, region 
		from = sq.region
		to   = region
	
		set_liaison from, to, sq
		set_liaison to, from , sq
	end


	#
	# Assign region to square with given offset from given square
	#
	def set_region square, x, y
		sq = square.rel [ x, y ]
		
		return unless sq.region.nil?

		if sq.water?
			# Set water so that we know it has been scanned
			sq.region = false
			return
		end

		regions = neighbor_regions sq

		if regions.empty?
			# No neighbors, assign a new region
			assign_region sq
			return
		end

		# Shuffle up in order to avoid very elognated regions
		#regions = regions.sort_by { rand }

		prefix = region_prefix( sq) 

		# Determine the first neighbor region with the given prefix
		region = nil
		regions.each do |r|
			$logger.info { "testing prefix #{ prefix } against #{ r/1000*1000 }, region #{r}" }
			if prefix == r/1000*1000
				region = r
				break
			end
		end

		unless region.nil?
			$logger.info { "Found #{ region }" }
			sq.region = region
			regions.delete region		# Don't liaison to current region
		else
			assign_region sq
		end
		
		# Assign liaisons for the new region
		regions.each do |r|
			assign_liaison sq, r
		end
	end

	#
	# Iterate over all squares in the view quadrant.
	# Square are traversed in straight lines, from the inside outwards.
	#
	def quadrant
		dim = @template.length
		(1...dim).each do |x|
			(0...dim).each do |y|
				next unless @template[x][y]
				yield x, y
			end
		end
	end

	#
	# Iterate over all squares in the view quadrant, by traversing
	# concentric squares from the inside out.
	#
	# Doesn't work too well, because regions can go around walls.
	# 
	def quadrant2
		dim = @template.length
		(1...dim).each do |radius|
			x = radius
			(0..radius).each do |y|
				next unless @template[x][y]
				yield x, y
			end

			y2 = radius
			(radius -1).downto(1) do |x2|
				next unless @template[x2][y2]
				yield x2, y2
			end
		end
	end


	def neighbor_regions sq
		ret = [] 

		[ :N, :E, :S, :W ].each do |dir|
			ret << sq.neighbor( dir ).region if sq.neighbor( dir).region
		end

		ret.uniq
	end



	public

	def region_prefix sq
		pref_row = sq.row/Distance.view_square_dist 
		pref_col = sq.col/Distance.view_square_dist 
		prefix = (pref_row*100 + pref_col)*1000
	end


	def assign_region sq, prefix = nil
		if prefix.nil?
			prefix = region_prefix sq
		end

		sq.region = prefix + @@counter
		@@counter += 1
	end


	def show_paths	paths
		str = ""

		all_paths each do |from, to, value|
			str << "...#{from}-#{to}: " + paths[key].join( ", ") + "\n"
		end

		str
	end

	def all_quadrant square
		quadrant {|x,y| 
			yield square.rel [ -x,  y ]
			yield square.rel [  y,  x ]
			yield square.rel [  x, -y ]
			yield square.rel [ -y, -x ]
		}
	end


	def find_regions square
		return if square.done_region

		$logger.info { "find_regions for #{ square }" }

		quadrant {|x,y| 
			set_region square, -x,  y 
			set_region square,  y,  x
			set_region square,  x, -y
			set_region square, -y, -x
		}

		square.done_region = true
		$logger.info { show_regions square }
	end


	def clear_path from, liaison
		d = Distance.get( liaison, from )

		# Must be next to liaison
		return false if d.row.abs > 1 or d.col.abs> 1

		# No obstructing water with liaison
		not from.water_close?
	end


	#
	# Given the from and to squares, determine
	# to which liaison we need to move in order
	# to go in the right direction.
	#
	# return: square if next square found
	#		  false  if no interim square needed; move directly.
	#                Prob doesn't occur any more
	#         nil    if path can not be determined
	#
	def path_direction from, to, check_skip_liaison = true
		path = find_path from, to, check_skip_liaison

		return nil if path.nil?
		return false if path.length < 2 

		liaison = get_liaison path[0], path[1]
		$logger.info { "liaison #{ liaison }, from #{ from }" }

if false
		# This occurs perhaps once per game; practically useless

		if liaison and clear_path from, liaison 
			$logger.info { "#{ from } clear to liaison. skipping."} 
			path = path[1,-1]
			return false if path.nil?
			return false if path.length < 2
			liaison = get_liaison path[0], path[1]
		end
end

		# If you have the choice, set path to next region 
		# requested

		if not check_skip_liaison 
#			$logger.info { "#{ from } already on liaison; adjusting path" }

			# Find a neighboring region that is the same as the
			# next requested region
			next_region = path[1]
			new_from = nil
			[ :N, :E, :S, :W ].each do |dir|
				if from.neighbor(dir).region == next_region
					new_from = from.neighbor(dir)
					$logger.info { "Found region #{ next_region} to #{ dir } at #{ liaison }; using that" }
					break
				end
			end


			unless new_from.nil?
				$logger.info { "Adjusting path to #{new_from} instead of liaison #{ liaison}" }
				liaison = new_from
			else
				$logger.info { "Could not find better point than liaison #{ liaison}" }
			end

#			if from == liaison
#				$logger.info { "Could not find good neighbor" }
#			end
		end

		liaison
	end


	#
	# NOTE: 
	#
	# In the case of searching for shortest path, it is still
	# possible that multiple paths are returned, ie. best interim results.
	#
	# Pre: input regions non-empty and validated
	#	
	def find_paths from_r, to_list_r, do_shortest = false, max_length = nil
		$logger.info { "searching from #{ from_r } for #{ to_list_r.length } destinations" }
		results = find_paths_cache from_r, to_list_r
		Fiber.yield

		# if nothing found, perform a search on all values at the same time
		if results.nil? or results.length == 0
			results = search_paths from_r, to_list_r, do_shortest, max_length
		else
			# remove distance info from results
			paths = []
			results.each do | path |
				paths << path[:path] 
			end
			results = paths
		end

		results
	end


	def get_non_results from_r, to_list_r
		non_results = []
		to_list_r.each do | to_r |
			next if to_r.nil?

			if get_non_path from_r, to_r
				non_results << to_r
			end
		end
		if non_results.length > 0
			$logger.info { "get_non_results found: #{ from_r }-#{ non_results}." }
		end

		non_results
	end


	#
	#
	#
	def search_paths from_r, to_list_r, do_shortest, max_length = nil
		to_list_r.compact!
		if to_list_r.length == 0
			$logger.info "to_list_r empty, not searching."
			return
		end

		$logger.info "Called search_paths"

		to_list_r -= get_non_results from_r, to_list_r

		results = LiaisonSearch.new( @liaison, do_shortest, max_length ).search from_r, to_list_r

		#
		# Store non-paths
		#
		# to-points without a found path are considered to be non-paths
		#
		# Don't do this for shortest path search with result, because 
		# we didn't consider all paths in that case
		#
		unless do_shortest and ( not results.nil? and results.length > 0 )
			found_to = []
			if results.nil? 
				found_to = to_list_r
			else
				results.each do |result|
					found_to << result[-1]
				end
			end
			notfound_to = to_list_r - found_to

			notfound_to.each do |to_r|	
				set_non_path from_r, to_r
				set_non_path to_r, from_r
			end
		end


		if results.nil? or results.length == 0 
			$logger.info "No results for search_paths"
			return nil 
		end

		# Store found paths in cache
		Region.add_paths results

		$logger.info {
			str = "Found results:\n"
			results.each do |result|
				str << "#{ result }\n"
			end

			str
		}

		results
	end


	#
	# Find path between given squares
	#
	def find_path from, to, check_skip_liaison = true
		# Assuming input are squares
		from_r = from.region
		to_r   = to.region

		if from_r.nil? or to_r.nil?
			$logger.info "one or both regions nil; can not determine path"
			return nil
		end
	
		result = find_path_regions from_r, to_r
		if result
			$logger.info { "found cached result #{ result }." }

			# Check if we are not already on liaison. If so, remove from list
			liaison = get_liaison result[0], result[1]
			if check_skip_liaison and liaison and from == liaison
				$logger.info { "Already at liaison, skipping it." }
				if result.length > 2 
					result = result[1..-1]
				else
					result = []
				end
			end		
		else
			$logger.info "putting search on backburner"
			Region.add_searches from, [ to ], true
		end

		result
	end


	#
	# Find path between given regions
	#
	def find_path_regions from_r, to_r
		#$logger.info { "find_path_regions #{ from_r}-#{to_r }" }

		# Test for unknown regions
		return nil unless from_r and to_r

		# Test same region
		return [] if from_r == to_r

		if get_non_path from_r, to_r
			$logger.info { "found cached non-result for #{ from_r }-#{to_r}." }
			return nil
		end

		get_path from_r, to_r
	end


	def store_path from_r, to_r, result

		if result
			Region.add_paths result
		else
			$logger.info { "store_path saving no-path #{ from_r } to #{ to_r }" }
			set_non_path from_r, to_r
			set_non_path to_r, from_r
		end
	end

	#
	# Refactored stuff
	#

	public

	#
	# Create a list of squares with the locations
	# of the given ants.
	#
	def self.ants_to_squares ants
		sq_ants = []

		ants.each do |ant|
			sq_ants << ant.square
		end

		sq_ants
	end


	private

	#
	# Make a list of regions for the given squares
	#
	def self.squares_to_regions to_list
		list = []

		to_list.each do |to|
			list << to.region unless to.region.nil?
		end

		list.uniq
	end

	#
	# Given a source region and a list of target regions,
	# find all available paths in the cache.
	#
	# Values are returned a array with element: [ path, path_length ]
	#	
	# Return: list of paths which connect source region to
	#         any of destination regions.
	#
	def find_paths_cache from_r, to_list_r
		$logger.info { "searching regions #{ to_list_r }" }


		to_list_r -= get_non_results from_r, to_list_r

		results = []
		to_list_r.each do |to_r|
			if to_r.nil?
				$logger.info "WARNING: nil detected for to_r"
				next
			end

			if from_r == to_r
				$logger.info { "same region #{ from_r }" }
				results << { :path => [], :dist => 0 } 
			else
				path = get_path_basic from_r, to_r
				results << path unless path.nil?
			end
		end

		# if we found something, we're done
		if results.length > 0
			$logger.info {
				str = "Found cached results:\n"
				results.each do |result|
					str << "#{ result }\n"
				end

				str
			}
		end

		results
	end


	public


	#
	# Make a sorted list of neighbouring ants from given input.
	# TODO: do_search not used 
	#
	def get_neighbors_sorted ant, in_ants, do_search = false, max_length = nil
		$ai.turn.check_maxed_out

		ants = in_ants.clone
		ants.delete_if { |a| ant.square == a.square }
		return [] if ants.length == 0

		$logger.info { "from: #{ ant } to #{ ants.length } ants; max_length: #{ max_length }." }

		ants_with_distance = $pointcache.get_sorted ant, ants, true

		# Let the backburner thread handle searching the path
		sq_ants   = Region.ants_to_squares ants
		Region.add_searches ant.square, sq_ants, false, max_length

		#$logger.info {
		#	str = "neighbors after sort:\n"
		#	ants_with_distance.each do |result|
		#		str << "#{ result }\n"
		#	end
		#
		#	str
		#}

		ants_with_distance
	end


	#
	# Get first liaison point that is not the same as from
	# if no liaisons found, to is returned
	# Only cache items are consulted - if no path found, nil is returned
	# 
	def first_liaison from, to
		return nil if from.region.nil? or to.region.nil?
		return to if from.region == to.region

		pathitem = $region.get_path_basic from.region, to.region
		return nil if pathitem.nil?

		path = pathitem[:path]
		return to if path.length < 2

		(0...path.length-1).each do |n|
			firstliaison = $region.get_liaison path[n], path[n+1]
			return firstliaison if firstliaison != from
		end

		to
	end

	def can_reach from, to
		return true if from == to
		
		if from.respond_to? :square
			from = from.square
		end
		if to.respond_to? :square
			to = to.square
		end

if false
		pathitem = get_path_basic from.region, to.region
	
		unless pathitem.nil?	
			$logger.info "Found path for #{ from }-#{to }"
			return true
		end

		walk = Distance.get_walk from, to
		if walk.length > 0 and walk[-1][0] == to
			$logger.info "Found walk for #{ from }-#{to }"
			return true
		end
end
		item =  $pointcache.get( from, to )
		if not item.nil? and not item[3]
			$logger.info "There's a known path for #{ from }-#{to }"
			return true
		end

		$logger.info "Can not reach #{ from }-#{to }"
		false
	end
end
