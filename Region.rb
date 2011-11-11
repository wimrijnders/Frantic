#require 'thread'
#$mutex = Mutex.new

class PointCache

	def initialize ai
		@cache = {}

		@hits = 0
		@misses = 0
		@replaces = 0
		@sets = 0
		@known = 0
		@invalidate_times = 0
		@invalidate_num = 0 

		@nil_pathitem = nil
		@zero_pathitem = { :path => [], :dist => 0 }
		@zero_distance_item = [ 0, @zero_pathitem, :STAY, false ]

		@add_points = []

		t = PointsThread.new self, @add_points		
		t.priority = -1

		# Thread.pass does NOT work!
		sleep 0.1	
		t.run
	end


	def get from, to, check_invalid = false, check_liaison = false

		raise "#{from} not a square" if not from.is_a? Square
		raise "#{to} not a square" if not to.is_a? Square

		if from == to
			# return a dummy item
			return @zero_distance_item
		end

		do_nil = true

		f = @cache[ from ]
		t = nil
		invalid = false

		unless f.nil?
			t = f[to]
			invalid = t[3] unless t.nil?
		end

		if not t.nil? 
			# items with distance one can be validated immediately
			if invalid and t[0] == 1
				t[3] = false
				invalid = t[3]
				t[1] = @zero_pathitem
			end	

			if not invalid

				$logger.info "hit #{from}-#{ to}: dist #{ t[0]}, dir #{ t[2] }"
				@hits += 1

				return t
			else
				if check_invalid
					return nil
				else
				 	result = t	
					do_nil = false
				end
			end
		end

		@misses += 1

		return nil if check_invalid 

# NOTE: Following creates more problems than it solves.
#       disabled thru default value of check_liaison

		# Try to find a path to the liaison
	if check_liaison
		firstliaison = $region.first_liaison from, to

		# ignore to as liaison, here above we concluded it is not in the cache 
		if not firstliaison.nil? and firstliaison != to

			# recursive call
			$logger.info "Getting liaison"
			item = get from, firstliaison, false, false
			unless item.nil?
				# Must be there, it is also called in first_liaison
				pathitem = $region.get_path_basic from.region, to.region
	
				#now we cheat a bit - contrive a cache item for further processing
				ret_item     = item.clone
				ret_item[0] += pathitem[:dist]
				ret_item[1]  = pathitem
				# Retain move
				ret_item[3]  = true
			
				$logger.info "Found liaison item #{ ret_item }"	
				result = ret_item 
			end
		end
	end	


		# initiate search here
		@add_points << [ from, to ]

		if do_nil	
			$logger.info { "Adding nilitem for #{ from}-#{ to}" }

			set to, from, nil, nil, true
			# Note that this returns a value
			tmp = set( from, to, nil, nil, true)
			if result.nil?
				result = tmp
			end
		end

		result
	end


	def	determine_move from, to
		next_sq = $region.path_direction from, to

		if false === next_sq
			# Move directly
			next_sq = to
		elsif next_sq.nil?
			# Can't be determined
			$logger.info "Move dir can not be determined."
			return nil
		end

		d = Distance.new( from, next_sq)
		move = d.dir from, true

		$logger.info "Determined move #{ move }"
		move
	end



	def set from, to, distance, item, invalid = false, move = nil
		raise "#{from} not a square" if not from.is_a? Square
		raise "#{to} not a square" if not to.is_a? Square

		$logger.info {
			"from-to => [ distance, item, move, invalid] : " +
			"#{ from }-#{ to } => [ #{ distance }, #{ item }, #{ move }, #{ invalid } ]"
		}

		if item.nil?
			item = @nil_pathitem
		end

		#$logger.info "Adding #{ from }, #{ to }"

		f = @cache[ from ]
		if f.nil?
			@cache[from] = {}
			f = @cache[from]
		end

		$logger.info { "f.nil?: #{f.nil?}, f[to]: #{ f[to] }" }

		if f[to].nil?
			@sets += 1

			if invalid
				d = Distance.new from, to
				distance = d.dist
				move = d.dir if move.nil?
			else
				move = determine_move from, to if move.nil?
			end

			f[to] = [distance, item, move, invalid ]

			$logger.info {
				"set: [ #{ distance }, #{item}, #{ move}, #{ invalid } ] "
			}

		elsif not invalid
			t = f[to]

			if t[3]  or t[0] > distance
				move = determine_move from, to if move.nil?

				$logger.info {
					"new item is better; old: #{ t }, new: [ #{ distance }, #{item}, #{ move}, false ]"
				}

				@replaces += 1 
				f[to] = [distance, item, move, false ]
			else
				@known += 1
			end

		end

		f[to]
	end


	def invalidate pathitem
		count = 0

Thread.exclusive {
		@cache.clone.each_pair do |k,v|
			v.clone.each_pair do |k2, v2|
				if v2[1] == pathitem
					v.delete k2
					count += 1
				end
			end

			if v.length == 0
				@cache.delete k
			end
		end
}

		$logger.info "Invalidated #{ count } items."
		@invalidate_times += 1
		@invalidate_num += count 
	end


	def status
		"pointcache status:
   hits      :%9d 
   misses    :%9d
   replaces  :%9d
   sets      :%9d
   known     :%9d
   invalidate: #{ @invalidate_times } times, #{ @invalidate_num } items
" % [ @hits, @misses, @replaces, @sets, @known  ]

	end

	#
	# Store full information for given input into the path cache.
	# 
	def retrieve_item from, to, in_path = nil, check_invalid = false

		# Note that param in_path is ignored if we get a cache hit
		item = get from, to, check_invalid

		if item.nil?
			if set_walk from, to, nil, true
				# We're done - there's a direct path
			else
			 
				# Following to determine path
				p = Pathinfo.new from, to, in_path
				path = p.path
				$logger.info "path #{ path }"
		
				newitem = nil	
				unless path.nil?
					# Hit the path cache - TODO: this is slightly inefficient,
					# since it also happens in Pathinfo
					if path.length > 2
						pathitem = $region.get_path_basic path[0], path[-1]
						unless pathitem.nil?
							# fill in the full walk as much as possible
							set_walk from, path[0], to
							set_regions from, to, pathitem
							set_walk path[-1], to
						end

#						pathitem = $region.get_path_basic path[0], path[-1]
#
#						unless pathitem.nil?
#							newitem = set from, to, p.dist, pathitem
#						end
					else
						$logger.info "WARNING: small path encountered; should not happen."
			
						# store anyway
						set to, from, p.dist, @zero_pathitem 
						newitem = set from, to, p.dist, @zero_pathitem 
					end
				end
			end
		end
	end


	def distance from, to, in_path = nil
		item = get from, to
		#item = retrieve_item from, to, in_path
		return nil if item.nil?
		item[0]
	end


	def direction from, to
		item = get from, to
		$logger.info "item #{ item }"
		#item = retrieve_item from, to

		return nil if item.nil?

		item[2]
	end


	def get_sorted from, to, valid_first = false


		# Following to take ants into account
		if from.respond_to? :square
			sq = from.square
		else
			sq = from
		end

		# randomize the input list a put a cap on it
		if to.length > 80
			$logger.info "Maxing and randomizing to-list"
			to = ( to.sort { rand} )[0,80]
		end

		list = []

Thread.exclusive { 
		to.each do |a|
			if a.respond_to? :square
				sq_to = a.square
			else
				sq_to = a
			end

			item = get sq, sq_to

			list << [ a, item ] unless item.nil?
		end

		# Sort list on distance; if specified, give precedence to valid
		# cache items
		list.sort! { |a,b| 
			if valid_first and a[1][3] and not b[1][3]
				 # a invalid, b not	
				 1
			elsif valid_first and not a[1][3] and b[1][3]
				 # b invalid, a not	
				-1
			else
				 a[1][0] <=> b[1][0]
			end
		}

		$logger.info {
			str = "After sort:\n"
			list.each do |result|
				str << "#{ result }\n"
			end

			str
		}
}


		# return list with distance info only
		ret = []
		list.each do |l|
			ret << [ l[0], l[1][0] ]
		end

		ret
	end


	# item - pathitem from path cache
	def set_regions from, to, item
		path = item[ :path ]
		$logger.info "entered path: #{ path }"

		if path.length > 2
			save_path from, to, path
			save_path from, to, path.reverse
		end
	end


	def save_path from, to, path
		#$logger.info "entered path: #{ path }"


		if path.length > 2
			# Don't rely on from and to, they appear to be wrong
			from = path[0]
			to   = path[-1]

			firstliaison = $region.get_liaison path[0], path[1]
			lastliaison = $region.get_liaison path[-2], path[-1]

			# This test may not be such a good idea, because the cache can be updated
			# next time the method is called, and more paths may be filled.
if false
			# Check if this path has been done before.
			testitem = get( firstliaison, lastliaison, true)
			unless testitem.nil?
				$logger.info "item already present, must have done this before. testitem: #{ testitem}"
				p = Pathinfo.new firstliaison, lastliaison, path
				$logger.info "path from cache: #{ p.path }"

				testdist = testitem[1][:dist] unless testitem[1].nil?

				if not testdist.nil? and testdist <= p.dist
					#$logger.info "Path is same, skipping"
					$logger.info "current solution is better, skipping"
					return
				end	
			end
end

			(0...(path.length() -2) ).each do |n|
		
				liaison1 = $region.get_liaison path[n], path[n+1]
				liaison2 = $region.get_liaison path[n+1], path[n+2]

				set_walk liaison1, liaison2, lastliaison
			end
		end
	end

	#
	# If full_only set, only store path if full path walked
	#
	# return true if full path walked
	def set_walk from, to, lastpoint = nil, full_only = false
		return false if from == to

		$logger.info { "entered #{ from }-#{to} => #{ lastpoint }" }

		lastpoint = to if lastpoint.nil?

		walk = Distance.get_walk from, to
		return false if walk.length == 0

		walked_full_path = ( walk[-1][0] == lastpoint )

		return false if not walked_full_path and full_only

		$logger.info {
			"walked full path #{ from }-#{to}" if walked_full_path
		}

		walk.each do |w|
			if walked_full_path
				# ignore regions altogether
				item = @zero_pathitem
				dist = w[2]
			else
				if w[0].region.nil?
					$logger.info "#{w[0]} region nil; skipping"
					next
				end

				item = $region.get_path_basic w[0].region, to

				if item.nil?
					$logger.info "#{w[0]} item nil; skipping"
					next
				end

				p = Pathinfo.new w[0], lastpoint, item[:path]

				if p.path.nil?
					$logger.info "#{p} path nil; skipping"
					next
				end

				dist = p.dist
			end


			# Don't add last point if full path reached
			unless w[2] == 0
				#$logger.info "Saving this item"
				set w[0], lastpoint, dist , item, false, w[1]
			end
		end

		walked_full_path
	end
end


class Pathinfo

	@@region = nil

	def self.set_region region
		@@region = region
	end

	def initialize from, to, path = nil
		@from, @to = from, to

		unless path
			path = $region.find_path from, to, false
		end

		if path
			@path = path
			@path_dist = Pathinfo.path_distance path
			@distance = calc_distance
		end

		self
	end


	def self.path_distance path
		return 0 if path.length <= 2
		$logger.info "entered"

		# Consult the cache first
		item = $region.get_path_basic path[0], path[-1]
		unless item.nil?
			return item[:dist]
		end

		# Not in cache; do the calculation
		$logger.info "path not in cache"

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

		# Perhaps TODO: store value into cache
		#               In that case, consult all other places where distance
		#               is calculated and stored to cache

		#$logger.info {
		#	path_length = path.length() - 1
		#	"Distance path #{ path } through #{ path_length } liasions: #{ total }." 
		#}

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

		#$logger.info {
		#	path_length = @path.length() - 1
		#	path_length = 0 if path_length < 0
		#	"Distance #{ @from.to_s }-#{ @to.to_s } through #{ path_length } liasions: #{ total }." 
		#}

		total
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

	NO_MAX_LENGTH      = -1
	DEFAULT_MAX_LENGTH = 10
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


		result = catch :done do 
			search_liaisons from_r, to_list_r, [from_r]
		end


		if @find_shortest and not result.nil? and result.length > 0
			# Shortest item is last in list.
			result = [ result[-1] ]
		end

		result
	end


	#
	#
	def find_first from_r, to_r
		$logger.info { "find_first #{ from_r }-#{ to_r }" }

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

		if @max_length != NO_MAX_LENGTH and current_path.length >= @max_length 
			$logger.info { "Path length >= #{ @max_length }; skipping" }
			return nil
		end

		cur = @liaison[from]

		if cur
			if cur[ to ]
				throw :done, current_path + [to]
			end

			cur.keys.each do |key|
				unless current_path.include? key
					search_liaison key, to, current_path + [key]
				end
			end
		end

		nil
	end



	def search_liaisons from, to_list, current_path
		to_list.compact!
		return nil if to_list.length == 0

		if @count >= MAX_COUNT
			$logger.info { "Count #{ @count } hit the max; aborting this search." }
			return []
		else
			@count +=1
		end
	
		# Safeguard to avoid too deep searches
		if @max_length != NO_MAX_LENGTH and current_path.length >= @max_length 
			$logger.info { "Path length >= #{ @max_length }; skipping" }
			return []
		end

		if @find_shortest and not @cur_best_dist.nil?
			dist = Pathinfo.path_distance current_path

			if dist > @cur_best_dist
				$logger.info { "search_liaisons cur dist #{ dist } > cur best #{ @cur_best_dist}; skipping" }
				return
			end
		end
	

		$logger.info { "search_liaisons searching #{ from }-#{ to_list }: #{ current_path }" }
		results = []
		found_to = []

		known_results = to_list & @cached_results.keys
		if known_results.length > 0
			$logger.info { "Already found results for targets #{ known_results}. Not searching these further." }
			to_list -= @cached_results.keys

			if to_list.length == 0
				$logger.info "to_list now empty. Not searching further."
				return []
			end
		end

		cur = @liaison[from]
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
							@cached_results[to] = result
						else
							next
						end
					else
						results << result 
						@cached_results[to] = result
					end

					found_to << to
				end
			end

			if @find_shortest and results.length > 0 
				# No point in looking further, any further paths will be longer
				return results
			end

			to_list -= found_to

			cur.keys.each do |key|
				unless current_path.include? key
					tmp = search_liaisons key, to_list, current_path + [key]
					results.concat tmp unless tmp.nil? 
				end
			end
		end

if false
		$logger.info "Pausing for a breather"
		sleep 0.02
		Thread.pass
end

		results
	end
end


class Region
	
	@@counter = 0
	@@ai = nil

	@@add_paths = []
	@@add_searches = []
	@@add_regions = []

	private 

	def do_thread
		t1 = Thread1.new self, @@add_paths
		t1.priority = -2

		t2 = Thread2.new self, @@add_searches
		t2.priority = -1

		t4 = BigSearchThread.new self, t2.my_list 

		t3 = RegionsThread.new self, @@add_regions
		t3.priority = -2

		liaisons_thread
	end

	def self.add_paths result
		$logger.info { "add_paths #{ result }" }
		@@add_paths.concat result
	end

	public 

	def self.add_searches from, to_list, do_shortest = false, max_length = nil
		sq_ants   = Region.ants_to_squares to_list
		$logger.info { "Adding search #{ from }-#{ sq_ants }, #{ do_shortest }, #{max_length}" }
		@@add_searches << [ from, sq_ants, do_shortest, max_length]
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

	#
	# Return relative offsets for a given square, for all the
	# points that are within the template.
	#
	def all_region
		dim = @template.length
		(1...dim).each do |x|
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


	def set_path_basic from, to, path, dist = nil
		$logger.info "entered path: #{ path }"
		ret = :new
		change = true

		if dist.nil?
			dist = Pathinfo.path_distance path
		end

		# path already present?
		prev_item = get_path_basic from, to 
		unless prev_item.nil?
			# Check if newer item better

			prev_path = prev_item[ :path ]
			prev_dist = prev_item[ :dist ]

			# Skip if these are the same solutions
			if path == prev_path
				return :known
			end

			if dist < prev_dist
				$logger.info { "Found shorter path for #{ from }-#{ to }: #{ path }; prev_dist: #{ prev_dist }, new_dist: #{ dist }" }
				ret = :replaced
				
				# Invalidate the point cache for this new path
				$pointcache.invalidate prev_item
				
			else
				change = false
			end
		end

		return :known if not change

		item = {
			:path => path,
			:dist => dist
		}

		unless @paths[ from ]
			@paths[from] = { to => item }
		else
			@paths[from][ to ] = item
		end

		$pointcache.set_regions from, to, item

		ret
	end

public

	def set_path path
		$logger.info "entered path: #{ path }"

		new_count = 0
		known_count = 0
		replaced_count = 0

		# Try to add the sub paths as well
		0.upto( path.length-2) do |i|
			# Doing longest path first
			( path.length-1).downto(i+1) do |j|
				changed = false
				from = path[i]
				to   = path[j]
				new_path = path[i..j]

				case set_path_basic from, to, new_path 
				when :new
					new_count += 1
				when :known
					# This path was known; so all sub-paths are also known.
					# No need to check these
					known_count += 1
					break
				when :replaced
					replaced_count += 1
				end
			end
		end

		#$logger.info { "path #{ path }: added #{ new_count }, known #{ known_count}" }
		[ new_count, known_count, replaced_count ]
	end



	#
	# Read given item from the cache.
	#
	# If found, returns array: [ path, path_length ]
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
	#
	#
	def set_region square, x, y
		sq = square.rel [ x, y ]

		if sq.region.nil?
			if sq.water?
				# Set water so that we know it has been scanned
				sq.region = false
				return
			end

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

	def assign_region sq, prefix = nil
		if prefix.nil?
			pref_row = sq.row/10 
			pref_col = sq.col/10 
			prefix = (pref_row*100 + pref_col)*1000
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


	def clear_path from, liaison
		d = Distance.new( liaison, from )

		# Must be next to liaison
		return false if d.row.abs > 1 or d.col.abs> 1

		# No obstructing water with liaison
		not from.water_close?
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
		path = find_path from, to, false

		return nil if path.nil?
		return false if path.length < 2 

		liaison = get_liaison path[0], path[1]
		$logger.info { "path_direction liaison #{ liaison }, from #{ from }" }

		if liaison and clear_path from, liaison 
			$logger.info { "path_direction #{ from } clear to  liaison. skipping."} 
			path = path[1,-1]
			return false if path.nil?
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
	def find_paths from, to_list, do_shortest = false, max_length = nil
		$logger.info { "searching from #{ from } for #{ to_list.length } destinations" }
		return nil if to_list.nil? or to_list.length == 0

		from_r = from.region
		to_list_r = Region.squares_to_regions to_list
		to_list_r.compact!
		if to_list_r.length == 0
			$logger.info "to_list_r empty, not searching."
			return
		end

		results = find_paths_cache from_r, to_list_r

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

		# Apparently, following is pointless
		#store_points from, to_list, results

		results
	end

	def store_points from, to_list, results
		return if results.nil? or results.length == 0
		$logger.info "entered"

		to_list.each do |to |
			from_r = from.region
			to_r   = to.region

			this_path = nil
			if from_r == to_r
				this_path = []
			else
				results.each do |path|
					if path[0] == from_r and path[-1] == to_r
						this_path = path
						break
					end
				end
			end

			unless this_path.nil?
				$logger.info "Adding #{from}-#{ to }: #{ this_path } to pointcache"
				$pointcache.retrieve_item from, to, this_path
			end
		end
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
	def find_path from, to, do_search = true
		# Assuming input are squares
		from_r = from.region
		to_r   = to.region

		if from_r.nil? or to_r.nil?
			$logger.info "one or both regions nil; can not determine path"
			return nil
		end
	
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
		elsif not do_search
			$logger.info "putting search on backburner"
			Region.add_searches from, [ to ], true
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
		ants = in_ants.clone
		ants.delete_if { |a| ant.square == a.square }
		return [] if ants.length == 0

		$logger.info { "from: #{ ant } to #{ ants.length } ants." }

		ants_with_distance = $pointcache.get_sorted ant, ants, true

		# Let the backburner thread handle searching the path
		sq_ants   = Region.ants_to_squares ants
		Region.add_searches ant.square, sq_ants, false, max_length

		$logger.info {
			str = "neighbors after sort:\n"
			ants_with_distance.each do |result|
				str << "#{ result }\n"
			end

			str
		}

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

		$logger.info "Can not reach #{ from }-#{to }"
		false
	end
end
