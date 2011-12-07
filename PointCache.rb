
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

		@zero_pathitem = { :path => [], :dist => 0 }

		# Fields: [ total_distance, path, next_move, invalid, path_distance ]
		@zero_distance_item = [ 0, @zero_pathitem, :STAY, false, 0 ]
	end


	def status
		"pointcache status:
   hits      :%9d 
   misses    :%9d
   replaces  :%9d
   sets      :%9d
   known     :%9d
   invalidate: #{ @invalidate_times } times, #{ @invalidate_num } items" % [ @hits, @misses, @replaces, @sets, @known  ]

	end


	def get from, to, check_invalid = false

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
		end

		if not t.nil? 
			invalid = t[3]

			# items with distance one can be validated immediately
			if invalid and t[0] == 1
				t[3] = false
				invalid = t[3]
				t[1] = @zero_pathitem
				t[4] = 0
			end	

			if not invalid

				#$logger.info "hit #{from}-#{ to}: dist #{ t[0]}, dir #{ t[2] }"

				if t[4] != t[1][:dist]
					$logger.info "Path distance changed; recalculating"
					path = t[1][:path]

					p = Pathinfo.new from, to, path 
					distance = p.dist
					move = determine_move from, to 

					$logger.info { "distance old: #{ t[0] }; new: #{ distance }" }

					t[0] = distance
					t[2] = move
					t[4] = t[1][:dist]
					@replaces += 1
				end

				@hits += 1
				return t
			else
				if check_invalid
					return nil
				else
				 	result = t	
					do_nil = false
					Region.add_searches from, [ to ]
				end
			end
		end

		@misses += 1

		return nil if check_invalid 


		if do_nil 
			#$logger.info { "Adding nilitem for #{ from}-#{ to}" }

			# Note that this returns a value
			tmp = set( from, to, nil, nil, true)
			if result.nil?
				result = tmp
			end
		end

		result
	end



	def	determine_move from, to
		$logger.info "entered"

		next_sq = $region.path_direction from, to, false

		if false === next_sq
			# Move directly
			next_sq = to
		elsif next_sq.nil?
			# Can't be determined
			$logger.info "Move dir can not be determined."
			return nil
		end

		d = Distance.get( from, next_sq)
		move = d.dir from, true

		$logger.info "Determined move #{ move }"
		move
	end



	def set from, to, distance, item, invalid = false, move = nil
		$logger.info "entered, move #{ move }"

		raise "#{from} not a square" if not from.is_a? Square
		raise "#{to} not a square" if not to.is_a? Square

		# safeguard initialization
		path_distance = 0

		# try direct path first
		if item.nil?
			d = Distance.get from, to
			if set_walk from, to, nil, true
				# It really is a direct path!
				$logger.info "It's a direct path"
				distance = d.dist
				item = @zero_pathitem
				move = d.dir
				invalid = false
				path_distance = 0
			else

				if from.region.nil?
					$logger.info "#{from} region nil; skipping"
				elsif to.region.nil?
					$logger.info "#{to} region nil; skipping"
				else
					item = $region.get_path_basic from.region, to.region
				end
				
				if not item.nil?
					path_distance = item[:dist]
				end

				if distance.nil? and not item.nil?
					p = Pathinfo.new from, to, item[:path]
	
					if p.path.nil?
						$logger.info "#{p} path nil; skipping"
					else
						distance = p.dist
					end
				end


				if not item.nil? and not distance.nil?
					move = determine_move from, to if move.nil?

					return nil if move.nil?

					invalid = false
				else
					$logger.info "not found; assume direct path"

					# d from here above
					distance = d.dist
					move = d.dir
					item = @zero_pathitem
					invalid = true
					path_distance = 0
	
					Region.add_searches from, [ to ]
				end
			end
		end

		result = [distance, item, move, invalid, path_distance ]

		#$logger.info {
		#	"from-to => [ distance, item, move, invalid] : " +
		#	"#{ from }-#{ to } => [ #{ distance }, #{ item }, #{ move }, #{ invalid } ]"
		#}

		f = @cache[ from ]
		if f.nil?
			@cache[from] = {}
			f = @cache[from]
		end

		if f[to].nil?
			@sets += 1
		else
			@known += 1
		end
		f[to] = result

		result	
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

						firstliaison = $region.get_liaison path[0], path[1]
						lastliaison = $region.get_liaison path[-2], path[-1]
						unless pathitem.nil?
							# fill in the full walk as much as possible
							set_walk from, firstliaison, to
							set_regions from, to, pathitem
							set_walk lastliaison, to
						end

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
		return nil if item.nil?
		item[0]
	end


	def direction from, to
		item = get from, to
		$logger.info "item #{ item }"

		return nil if item.nil?

		item[2]
	end


	def get_sorted from, to, valid_first = false
$logger.info "entered"


		# Following to take ants into account
		if from.respond_to? :square
			sq = from.square
		else
			sq = from
		end

		# randomize the input list to put a cap on it
		max_cap = 80

		if $ai.turn.maxed_out?
			# Make the value even smaller
			$logger.info "maxed_out: tightening sort limit"
			max_cap = max_cap/4
		end

		if to.length > max_cap
			$logger.info "Maxing and randomizing to-list"
			to = to.sample( max_cap)
		end

		list = []

		to.each do |a|
$logger.info "to ant: #{ a}"
			if a.respond_to? :square
				sq_to = a.square
			else
				sq_to = a
			end

			item = get sq, sq_to

			list << [ a, item ] unless item.nil?

			$ai.turn.check_maxed_out
		end
$logger.info "done get"

		PointCache.sort_valid list, valid_first
$logger.info "done sort"

		$ai.turn.check_maxed_out

		#$logger.info {
		#	str = "After sort:\n"
		#	list.each do |result|
		#		str << "#{ result }\n"
		#	end

		#	str
		#}

		# return list with distance info only
		ret = []
		list.each do |l|
			ret << [ l[0], l[1][0] ]
		end

$logger.info "done"
		ret
	end


	# Sort list on distance; if specified, give precedence to valid
	# cache items
	def self.sort_valid list, valid_first = true
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

			(0...(path.length() -2) ).each do |n|
		
				liaison1 = $region.get_liaison path[n], path[n+1]
				liaison2 = $region.get_liaison path[n+1], path[n+2]

				set_walk liaison1, liaison2, lastliaison
			end
		end
	end

	def has_direct_path from, to
		Distance.direct_path? from, to
	end

	#
	# If full_only set, only store path if full path walked
	#
	# return true if full path walked.
	#
	def set_walk from, to, lastpoint = nil, full_only = false
		return false if from == to

		$logger.info { "entered #{ from }-#{to} => #{ lastpoint }" }

		lastpoint = to if lastpoint.nil?

		walk = Distance.get_walk from, to
		return false if walk.length == 0

		walked_full_path = ( walk[-1][0] == lastpoint )

		$logger.info {
			"walked full path #{ from }-#{to}" if walked_full_path
		}

		return false if not walked_full_path and full_only

		walk.each do |w|
			item = nil
			dist = nil

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


	#
	# Path has changed for given path_item, recalculate relevant
	# items in the pointcache
	#
	def recalc_pointcache path_item
		$logger.info "entered"
		count = 1

		# clone()'s are needed; otherwise you'll get set-errors
		# in the hash elsewhere
		@cache.keys.clone.each do |from|

			Fiber.yield unless Fiber.current.nil?

			@cache[from].keys.clone.each do |to|
				if count % 100 == 0
					Fiber.yield unless Fiber.current.nil?
				end

				cache_item = @cache[from][to]
				if path_item.object_id == cache_item[1].object_id
					p = Pathinfo.new from, to, cache_item[1][:path]
					distance = p.dist
					move = determine_move from, to

					$logger.info { "New distance: #{ distance}; move: #{ move }" }

					cache_item[0] = distance
					cache_item[1] = move

					@replaces += 1

					count += 1
				end
			end
		end		

		$logger.info "done"
	end
end

