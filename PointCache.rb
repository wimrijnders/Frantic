
class PointCache

	def initialize ai
		@zero_pathitem = { :path => [], :dist => 0 }
		@zero_distance_item = [ 0, @zero_pathitem, :STAY, false ]
	end


	def get from, to, check_invalid = false

		raise "#{from} not a square" if not from.is_a? Square
		raise "#{to} not a square" if not to.is_a? Square

		if from == to
			# return a dummy item
			return @zero_distance_item
		end

		# Note that this returns a value
       	set( from, to, nil, nil, true)
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

		found = false

		while true
			if from.region.nil?
				$logger.info "#{from} region nil; skipping"
				break
			end

			if to.region.nil?
				$logger.info "#{to} region nil; skipping"
				break
			end

			item = $region.get_path_basic from.region, to.region

			if item.nil?
				$logger.info "#{item} item nil; skipping"
				break
			end

			p = Pathinfo.new from, to, item[:path]

			if p.path.nil?
				$logger.info "#{p} path nil; skipping"
				break
			end

			distance = p.dist
			found = true
			invalid = false
			break
		end


		unless found 
			d = Distance.new from, to
			distance = d.dist
			move = d.dir if move.nil?
			invalid = true
		else
			move = determine_move from, to if move.nil?
		end

		result = [distance, item, move, invalid ]

		$logger.info {
			"from-to => [ distance, item, move, invalid] : " +
			"#{ from }-#{ to } => [ #{ distance }, #{ item }, #{ move }, #{ invalid } ]"
		}

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

