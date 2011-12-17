
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
				t[1] = @zero_pathitem
				t[3] = false
				t[4] = 0

				invalid = t[3]
			end	

			if not invalid

				#$logger.info "hit #{from}-#{ to}: dist #{ t[0]}, dir #{ t[2] }"

				if !check_invalid and  t[4] != t[1][:dist]
					$logger.info "Path distance changed; recalculating"
					path = t[1][:path]

					distance = Pathinfo.total_path_distance from, to, path, t[1][:dist]
					move, direct = determine_move from, to 

					# If no move returned, never mind; we try again later
					# and see if the backburner has completed it.
					unless move.nil?
						$logger.info { "distance old: #{ t[0] }; new: #{ distance }" }

						t[0] = distance
						t[2] = move
						t[4] = t[1][:dist]
						@replaces += 1
					end
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



	def	next_square from, to
		$logger.info "entered"

		next_sq = $region.path_direction from, to, false

		if false === next_sq
			# Move directly
			next_sq = to
		elsif next_sq.nil?
			$logger.info "Next square can not be determined."
		end

		next_sq


	end

	def	determine_move from, to
		$logger.info "entered"

		# No point in retrieving item from cache; the whole
		# point of this routine is to create or replace an
		# existing item. It is called from get and set.

		next_sq = next_square from, to
		if next_sq.nil?
			$logger.info "Move dir can not be determined."
			return nil
		end

		item = get from, next_sq, true
		if not item.nil?
			# Cached item present till liaison; use that
			ret =[ item[2], !item[3] ]		# Second param means 'direct route present'
											# This translates to a 'valid' cache item, ie 'not invalid',
											# which is what you read there
			$logger.info "Move from cache returns #{ ret }"
			return ret 
		end

		# No cached item; try to make a path to the liaison
		direct = set_walk from, next_sq, nil, true

		if direct
			# At this point, the value has been stored in the pointcache
			# Retrieve it without triggering a new set for the move
			item = get from, next_sq, true

			if item.nil?
				$logger.info "WARNING: expected non-nil item but got one anyway"
				return nil
			end

			$logger.info "Determined move #{ item[2] }"
			[ item[2], true]
		else	
			$logger.info "Move dir can not be determined from set_walk."
			nil
		end
	end


	def add_cache from, to, result
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
	end


	def set from, to, distance, item, invalid = false, move = nil
		$ai.turn.check_maxed_out

		$logger.info "entered, from #{ from}, to #{ to }, move #{ move }"

		raise "#{from} not a square" if not from.is_a? Square
		raise "#{to} not a square" if not to.is_a? Square

		if item.nil?
			# try direct path first
			d = Distance.get from, to
			if set_walk from, to, nil, true
				$logger.info "direct path from-to"
				# At this point, the new value has been saved by a recursive
				# call to set(). Retrieve it without triggering a new set.
				result = get from, to, true
				#result = [ d.dist, @zero_pathitem, d.dir, false, 0 ]
				#add_cache from, to, result
				return result
			end

			if from.region.nil?
				$logger.info "from #{from} region nil; skipping"
				return nil
			elsif to.region.nil?
				$logger.info "to #{to} region nil; skipping"
				return nil
			end

			item = $region.get_path_basic from.region, to.region
			if not item.nil?
				distance = Pathinfo.total_path_distance from, to, item[:path], item[:dist]
				path_distance = item[:dist]
			end
		else
			#$logger.info "Already have item"

			# If item is present, distance is also present
			# No need to calculate it

			path_distance = item[:dist]
		end

		if move.nil?
			move, direct = determine_move from, to
			invalid = false if direct and not move.nil?
		end

		result = [distance, item, move, invalid, path_distance ]


		if result[0].nil? or
		   result[1].nil? or
		   result[2].nil? or
		   result[3].nil? or
		   result[4].nil?

			#$logger.info "result #{ result } not complete; assume direct path"
			d = Distance.get from, to
			result = [ d.dist, nil, d.dir, true, 0 ]

			Region.add_searches from, [ to ]
		end

		add_cache from, to, result
		result	
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
			#$logger.info "to ant: #{ a}"
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


	#
	# Note that the check may be strictly speaking invalid.
	# It is possible to have a clear path, but that pointcache
	# stores a path through a liaison.
	#
	# Let's hope that the pathfinder backburners can recalc that 
	# eventually.
	# 
	def is_direct_path item
		!item.nil? and !item[3]  and item[1] == @zero_pathitem
	end


	def has_direct_path from, to
		return true if from == to

		# Silly to recalc this if already in pointcache
		# In any case, if it isn't, the call to get will put it there
		#Distance.direct_path? from, to

		from = from.square if from.respond_to? :square
		to = to.square if to.respond_to? :square

		item = get from, to

		ret = is_direct_path item

		$logger.info { "#{from}-#{to} direct: #{ ret }" }	
		ret
	end


	def can_reach from, to
		return true if from == to
		
		from = from.square if from.respond_to? :square
		to = to.square if to.respond_to? :square

		item =  get from, to
		if not item.nil? and not item[3]
			$logger.info "There's a known path for #{ from }-#{to }"
			return true
		end

		$logger.info "Can not reach #{ from }-#{to }"
		false
	end

	#
	# If full_only set, only store path if full path walked
	#
	# return true if full path walked.
	#
	def set_walk from, to, lastpoint = nil, full_only = false, complete_path = false
		return false if from == to

		$logger.info { "entered #{ from }-#{to} => #{ lastpoint }" }
		lastpoint = to if lastpoint.nil?

		if complete_path
			# Perhaps the path has been found in the meantime; check
			tmp = get from, lastpoint , true
			unless tmp.nil?
				$logger.info { "walk #{from}-#{to} already found" }
				return false
			end
		end

		walk = Distance.get_walk from, to, complete_path
		if walk.nil? or walk.empty?
			return false
		end

		walked_full_path = ( walk[-1][0] == lastpoint )

		if walked_full_path
			$logger.info { "walked full path #{ from }-#{to}" }
		else
			# TODO: Prob never reached any more; check

			$logger.info { "Did not walk full path #{ from }-#{to}" }

			# trigger complete search
			WalkFiber.add_list [ from, lastpoint ]

			return false if full_only
		end


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

				dist = Pathinfo.total_path_distance w[0], lastpoint, item[:path], item[:dist]
			end


			# Don't add last point if full path reached
			unless w[2] == 0
				#$logger.info "Saving #{ w[0] }-#{lastpoint}"
				tmp = get w[0], lastpoint, true 
				#$logger.info "tmp #{ tmp }"
				if not is_direct_path tmp
					set w[0], lastpoint, dist , item, false, w[1]
				else
					# Item has already been added; so the rest of the path
					# has been added as well
					$logger.info "rest of path is known"
					break
				end
			end
		end

		walked_full_path
	end
end

