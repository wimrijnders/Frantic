
class Pathinfo
	@@region = nil

	def self.set_region region
		@@region = region
	end

	def initialize from, to, path = nil
		@from, @to = from, to

		if path
			@path = path
			@path_dist = Pathinfo.path_distance path
		else
			# NOTE: from and to are squares here
			path = $region.find_path from, to
			if path
				item = $region.get_path_basic path[0], path[-1]
				$logger.info { "get_path_basic returned nil: #{ item.nil? }" }
				unless item.nil?
					@path = item[:path]
					@path_dist = item[:dist]
				else
					@path = path
					@path_dist = Pathinfo.path_distance path
				end
			end

			unless item.nil?
			end
		end

		@distance = calc_distance if @path
	end

	def self.path_distance path
		return 0 if path.length <= 2

		prev = nil
		total = 0
		0.upto(path.length-2) do |n|
			cur = @@region.get_liaison path[n], path[n+1]

			unless prev.nil?
				dist = Distance.new prev, cur
				total += dist.dist
			end

			prev = cur
		end

		path_length = path.length() - 1
		$logger.info { "Distance path #{ path } through #{ path_length } liasions: #{ total }." }
		total
	end


	def calc_distance
		total = 0
		if @path.nil? or @path.length < 2
			# There is no path; calculate distance between from and to
			dist = Distance.new @from, @to
			total += dist.dist
		else
			cur = @@region.get_liaison @path[0], @path[1]
			dist = Distance.new @from, cur
			total += dist.dist

			cur = @@region.get_liaison @path[-2], @path[-1]
			dist = Distance.new cur, @to
			total += dist.dist

			total += @path_dist
		end

		path_length = @path.length() - 1
		path_length = 0 if path_length < 0
		$logger.info { "Distance #{ @from.to_s }-#{ @to.to_s } through #{ path_length } liasions: #{ total }." }

		total
	end

	def path?
		!@path.nil?
	end

	def dist
		@distance
	end

	def self.shortest_path from, to_list
		results = $region.find_paths from, to_list, true

		return nil if results.nil? or results.length == 0

		# Determine shortest path from the list of results
		# Note that this is not the actual path length, as it excludes
		# the real from and to squares
		best_path = nil
		best_dist = -1
		results.each do |path|
			# Same region always wins
			if path.length == 0
				best_path = path
				best_dist = 0
				break
			end

			dist = path_distance path


			if best_path.nil? or dist < best_dist
				best_path = path
				best_dist = dist
			end	
		end

		$logger.info { "Shortest path: #{ best_path }, dist: #{ best_dist}" }
		best_path
	end
end


class LiaisonSearch
	def initialize cache, find_shortest = false, max_length = nil
		@liaison = cache
		@find_shortest = find_shortest

		if max_length.nil?
			@max_length = 15
		else
			@max_length = max_length 
		end
	end


	def search from_r, to_list_r
		@cur_best_dist = nil;
		$logger.info "searching shortest path" if @find_shortest

		if @find_shortest and to_list_r.include? from_r 
			# Same region always wins
			$logger.info { "search_liaisons found same region" }
			return [ [] ]
		end


		result = catch :done do 
			search_liaisons from_r, to_list_r, [from_r]
		end

		result
	end


	#
	# NOTE: Apparently not called any more;
	#       Verify and remove if OK.
	#
	def find_first from_r, to_r
		$logger.info { "find_first #{ from }-#{ to_list }" }

		# Same region always wins
		if from_r == to_r 
			$logger.info { "search_liaison found same region" }
			return []
		end

		result = catch :done do
			search_liaison from_r, to_r, [from_r]
		end

		result
	end


	private

	#
	# Search for first path between from and to.
	#
	def search_liaison from, to, current_path
		$logger.info { "search_liaison searching #{ from }-#{ to }: #{ current_path }" }
		if current_path.length >= @max_length 
			$logger.info { "Path length >= #{ @max_length }; skipping" }
			return nil
		end

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



	def search_liaisons from, to_list, current_path
		return nil if to_list.length == 0
	
		# Safeguard to avoid too deep searches
		if current_path.length >= @max_length 
			$logger.info { "Path length >= #{ @max_length }; skipping" }
			return []
		end
	

		$logger.info { "search_liaisons searching #{ from }-#{ to_list }: #{ current_path }" }
		cur = @liaison[from]
		results = []
		found_to = []

		if cur
			to_list.each do |to|

				if cur[ to ]
					result = current_path + [to]
					$logger.info { "search_liaisons found path#{ from }-#{ to_list }: #{ result }" }

					if @find_shortest
						dist = Pathinfo.path_distance result

						if @cur_best_dist.nil? or dist < @cur_best_dist
							$logger.info { "search_liaisons path is new shortest" }
							@cur_best_dist = dist
							results << result 
						else
							next
						end
					else
						results << result 
					end

					found_to << to
				end
			end

			if @find_shortest and results.length > 0 
				# No point in looking further, any further paths will be longer
				return results
			end

			to_list -= found_to

			cur.each_key do |key|
				unless current_path.include? key
					tmp = search_liaisons key, to_list, current_path + [key]
					results.concat tmp unless tmp.nil? 
				end
			end
		end

		results
	end
end


class Region
	
	@@counter = 0
	@@ai = nil

	@@add_paths = []

	private 

	def do_thread
		@add_path_thread = Thread.new do
			$logger.info "Thread activated"

			longest_diff = nil
			longest_count = nil

			doing = true
			while doing
				$logger.info "Thread waiting"
				sleep 0.2 while @@add_paths.length == 0

				count = 0
				start = Time.now
				while @@add_paths.length > 0
					# Remove first item
					path = @@add_paths.pop
					next if path.length == 0

					from_r = path[0]
					to_r   = path[-1]
					$logger.info { "Thread saving path #{ from_r } to #{ to_r }: #{ path }" }
					# Cache the result
					set_path from_r, to_r, path
					set_path to_r, from_r, path.reverse

					count += 1
				end
				$logger.info {
					diff = ( (Time.now - start)*1000 ).to_i

					if longest_diff.nil? or diff > longest_diff
						longest_diff = diff
						longest_count = count

					end
					str = " Longest: #{ longest_count } in #{ longest_diff } msec"

					"Thread added #{ count } results in #{ diff} msec. #{ str }" 
				}

			end

			$logger.info "Thread closing down."
		end
	end

	def self.add_paths result
		$logger.info { "add_paths #{ result }" }
		@@add_paths.concat result
	end

	public 

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

		do_thread
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
						r = "__" + sq.region.to_s
					elsif sq.region < 100
						r = "_" + sq.region.to_s
					else
						r = sq.region.to_s
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

			unless @liaison[ from ]
				@liaison[from] = { to => square }
			else
				@liaison[from][ to ] = square
			end
			$logger.info { "#{ square } liaison for #{ from }-#{ to }." }

			set_path from, to, [ from, to]

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


	def set_path_basic from, to, path, dist = nil
		if dist.nil?
			dist = Pathinfo.path_distance path
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
	end


	def set_path from_old, to_old, path
		# We assume here that these are new paths
		# Try to add the sub paths as well

		0.upto( path.length-2) do |i|
			# Doing longest path first
			( path.length-1).downto(i+1) do |j|
				changed = false
				from = path[i]
				to   = path[j]
				new_path = path[i..j]
				prev_item = get_path_basic from, to 

				if prev_item.nil?
					set_path_basic from, to, new_path 
					$logger.info { "Added new path #{ from }-#{ to }: #{ new_path }" }
					changed = true
				else
					prev_path = prev_item[ :path ]
					prev_dist = prev_item[ :dist ]

					# Skip if these are the same solutions
					if new_path != prev_path

						new_dist  = Pathinfo.path_distance new_path 

						if new_dist < prev_dist
							$logger.info { "Found shorter path for #{ from }-#{ to }: #{ new_path }; prev_dist: #{ prev_dist }, new_dist: #{ new_dist }" }
							set_path_basic from, to, new_path, new_dist 
							changed = true
						end
					end
				end

				if not changed
					# This path was known; so all sub-paths are also known.
					# No need to check these
					$logger.info "Known path #{ new_path }; skipping sub-paths"
					break
				end
			end
		end
	end

public


	#
	# Read given item from the cache.
	#
	# If found, returns array: [ path, path_length ]
	# If not found, return nil
	#
	def get_path_basic from, to
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
	#
	#
	def set_region square, x, y
		sq = square.rel [ x, y ]
		if !sq.region
			return if sq.water?

			# If no region present, fill one in
			# Check neighbor regions, and select that if present	
			regions = neighbor_regions sq

			# Shuffle up in order to avoid very elognated regions
			regions = regions.sort_by { rand }

			if regions.length > 0
				regions.each do |region|
					unless sq.region
						# First region we encounter, we use for current square
						sq.region = region
					else
						# For the rest, we are liaison
						from = sq.region
						to   = region
	
						set_liaison from, to, sq
						set_liaison to, from , sq
					end
				end
			else 
				# No neighbors, fill in a new region
				assign_region sq
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
		ret = [] 

		[ :N, :E, :S, :W ].each do |dir|
			ret << sq.neighbor( dir ).region if sq.neighbor( dir).region
		end

		ret.uniq
	end



	public

	def assign_region sq
		sq.region = @@counter
		@@counter += 1
	end

	def show_paths	paths
		str = ""

		all_paths each do |from, to, value|
			str << "...#{from}-#{to}: " + paths[key].join( ", ") + "\n"
		end

		str
	end


	def find_regions square
		return if square.done_region

		$logger.info { "find_regions for #{ square }" }

		dim = @template.length
		quadrant {|x,y| set_region square, -x,  y }
		quadrant {|x,y| set_region square,  y,  x }
		quadrant {|x,y| set_region square,  x, -y }
		quadrant {|x,y| set_region square, -y, -x }

		square.done_region = true
		$logger.info { show_regions square }
	end

	#
	# Given the from and to squares, determine
	# to which liaison square we need to move in order
	# to go in the right direction.
	#
	# return: square if liaison square found
	#		  false  if no liason needed
	#         nil    if path can not be determined
	#
	def path_direction from, to
		path = $region.find_path from, to, false

		return nil if path.nil?
		return false if path.length < 2 

		liaison = get_liaison path[0], path[1]
		$logger.info { "path_direction liaison #{ liaison }, from #{ from }" }

		if liaison and liaison.row == from.row and liaison.col == from.col
			$logger.info { "path_direction #{ from } already at liaison. skipping."} 

			path = path[1,-1]
			return nil if path.nil?
			return false if path.length < 2
			liaison = get_liaison path[0], path[1]
		end

		liaison
	end


	#
	# NOTE: 
	#
	# In the case of searching for shortest path, it is still
	# possible that multiple paths are returned, ie. best interim results.
	#	
	def find_paths from, to_list, do_shortest = false
		$logger.info { "find_paths searching to #{ from } for #{ to_list.length } ants" }
		return nil if to_list.nil? or to_list.length == 0

		from_r = from.region
		to_list_r = Region.squares_to_regions to_list

		results = find_paths_cache from_r, to_list_r


		# if nothing found, perform a search on all values at the same time
		if results.length == 0
			results = search_paths from_r, to_list_r, do_shortest
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
			$logger.info "No results for find_paths"
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
	def find_path from, to, do_search = true
		# Assuming input are squares
		from_r = from.region
		to_r   = to.region
	
		result = find_path_regions from_r, to_r, do_search
		if result
			$logger.info { "found cached result #{ result }." }

			# Check if we are not already on liaison. If so, remove from list
			liaison = get_liaison result[0], result[1]
			if liaison and from == liaison
				$logger.info { "Already at liaison, skipping it." }
				if result.length > 2 
					result = result[1..-1]
				else
					result = []
				end
			end		
		end

		result
	end


	#
	# Find path between given regions
	#
	def find_path_regions from_r, to_r, do_search = true
		#$logger.info { "find_path_regions #{ from_r}-#{to_r }" }

		# Test for unknown regions
		return nil unless from_r and to_r

		# Test same region
		return [] if from_r == to_r

		if get_non_path from_r, to_r
			$logger.info { "found cached non-result for #{ from_r }-#{to_r}." }
			return nil
		end

		result = get_path from_r, to_r
			
		# Only do search if specified
		if not result and do_search
			result = LiaisonSearch.new( @liaison).find_first from_r, to_r

			store_path from_r, to_r, [ result ]
		end

		result
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
			list << to.region
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
		$logger.info { "find_paths_cache searching regions #{ to_list_r }" }

		# Same region always wins
		if to_list_r.include? from_r
			$logger.info { "find_paths_cache same region #{ from_r }" }
			return [ { :path => [], :dist => 0 } ]
		end

		to_list_r -= get_non_results from_r, to_list_r

		results = []
		to_list_r.each do |to_r|
			path = get_path_basic from_r, to_r
			results << path unless path.nil?
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
	# Only the cache is consulted.
	#
	def get_neighbors_sorted ant, ants, do_search = false
		# Remove current ant from list.
		tmp = ants.clone
		tmp.delete ant
		return [] if tmp.length == 0

		$logger.info "Entered get_neighbors_sorted"
		$logger.info { "Ants : #{ ants }" }

		sq_ants   = Region.ants_to_squares tmp
		$logger.info { "Ant squares: #{ sq_ants }" }

		from_r = ant.square.region
		to_list_r = Region.squares_to_regions sq_ants

		paths = find_paths_cache from_r, to_list_r
		if paths.length == 0 and do_search
			found = search_paths from_r, to_list_r, false, 5
	
			if found and found.length > 0
				# Add distance information to results
				# NB: this distance is not used later on
				found.each do | path |
					paths << { :path => path, :dist => Pathinfo.path_distance( path ) }
				end
			end
		end

		# Connect ants to the found paths and determine total distance
		ants_with_distance = []
		ants.each do |a|
			region = a.square.region
			paths.each do |l|
				if l[:path][-1] == region
					ants_with_distance << [ a, Pathinfo.new(ant.square, a.square, l[:path]).dist ]
					break
				end
			end
		end

		$logger.info {
			str = "neighbor ants found:\n"
			ants_with_distance.each do |result|
				str << "#{ result }\n"
			end

			str
		}

		# Sort the list
		ants_with_distance.sort! { |a,b| a[1] <=> b[1] }

		$logger.info {
			str = "neighbor ants after sort:\n"
			ants_with_distance.each do |result|
				str << "#{ result }\n"
			end

			str
		}

		ants_with_distance
	end
end
