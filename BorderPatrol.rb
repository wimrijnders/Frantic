class BorderPatrol
	def initialize
		@complete_regions = []

		@regions = []
		@liaisons = []
		@done_liaisons = []
		@last_liaison = nil

		@exits = {}
	end


	def all_neighbor_regions_present region
		@exits[region][:exits].each_key do |k|
			return false if @exits[k].nil?

			# Combined isolated regions can have this. 
			if @exits[k][:count].nil?
				$logger.info "WARNING: region #{ k } has no count."
				return false
			end
		end

		true
	end

	def delete_exit from, to
		if @exits[from][:exits].length == 1
			$logger.info { "WARNING: only one exit left for #{ from }, not deleting" }
			return 
		end

		@exits[from][:exits].delete to 
	end


	def hilo_counts region
		cur_item = @exits[region]

		highest = nil
		lowest = nil
		cur_count = cur_item[:count]
		cur_item[:exits].each_key do |r|
			item = @exits[r]

			# If item or count not present, can not do this check
			if item.nil?
				return [nil, nil]
			end

			count = item[:count]
			if count.nil?
				return [nil, nil]
			end

			if lowest.nil? or count < lowest
				lowest = count
			end

			if highest.nil? or count > highest
				highest = count
			end
		end

		[highest, lowest]
	end

	# Pre: all neighbors are top items in the exits hash
	def analyze_region cur_region, cur_item

		$logger.info "entered, #{ cur_region }"

		# Check there are no paths to higher regions,
		# or there is only a single exit.
		single_exit = false
		if cur_item[:exits].length == 1
			single_exit = true
		end



		if single_exit
			# Current region is a dead end, or has exactly one 
			# defined outer exit (no other exit on the way back); always remove
			# from neighbor. 
			cur_item[:exits].each_key do |k|
				delete_exit k, cur_region

				if cur_item[:done]
					$logger.info "Redoing analysis for region #{ k }"
					analyze_region k, @exits[k] 
				end
			
			end
		end

		cur_count = cur_item[:count]
		highest, lowest = hilo_counts cur_region

		if highest.nil? 
			# Perhaps this always goes well; not sure, leaving it in.
			$logger.info "can't complete analysis for #{ cur_region }; retrying later on"
			return
		end

		if highest < cur_count
			# There are no higher exits; this is effectively a dead end
			$logger.info "Reached local max at #{ cur_region }"

			# inform all neighbors
			cur_item[:exits].each_key do |r|
				delete_exit r, cur_region

				if cur_item[:done]
					$logger.info "Redoing analysis for region #{ r }"
					analyze_region r, @exits[r] 
				end
			end
		elsif highest == cur_count
			# Cut ties if these regions have no higher neighbor
			cur_item[:exits].each_key do |r|
				hi, lo = hilo_counts r
		
				if hi.nil? 
					$logger.info "can't complete analysis for #{ cur_region } 2; retrying later on"
					return
				end

				if hi <= highest
					$logger.info "#{ cur_region } neighbor #{ r } has no higher count than #{ highest }; cutting ties"

					delete_exit cur_region, r
					delete_exit r, cur_region

					if cur_item[:done]
						$logger.info "Redoing analysis for region #{ r }"
						analyze_region r, @exits[r] 
					end
				end
			end
		end	



		# Sanity check; exit(s) we're going to,
		# should have an exit to a different region
		$logger.debug {
			break if cur_item[:exits].length > 1

			cur_item[:exits].clone.each_key do |k|
				v = @exits[k]
				next if v.nil?

				tmp = v[:exits].keys - [cur_region]
				if tmp.length == 0
					raise "no other exits from #{ cur_region } through #{k}"
				end
			end
		}

		cur_item[:done] = true
	end

	def analyze_regions
		# Update counts
		@exits.each_pair do |k,v|
			next if v[:done]


			# It possible that count has not been set, when
			# given region is not connected to a hill region.
			# Keep on retrying till we got it
			if v[:count].nil?
				set_distance_count k
				next if v[:count].nil?
			end

			next unless all_neighbor_regions_present k

			analyze_region k, v
		end

		show_exits
	end


	def show_exits
		$logger.info {
			str = ""
			@exits.each_pair do |k,v|
				str2 = ""
				v.each_pair do |k2,v2|
					str2 << "      #{ k2 } => #{ v2 }\n"
				end
				str << "   #{ k } => {\n#{ str2 }   }\n"
			end
			"exits: {\n#{ str }}"
		}
	end

	def set_distance_count cur_region
		if $ai.hills.my_hill_region? cur_region
			@exits[cur_region][:count] = 0
		else
			regions = @exits[cur_region][:exits].keys

			# get the lowest count from the surrounding regions
			lowest = nil
			regions.each do |r|
				item = @exits[r]
				next if item.nil?
				count = item[:count]
				next if count.nil?

				if lowest.nil? or count < lowest
					lowest = count
				end
			end

			unless lowest.nil?
				cur_count = lowest + 1
				@exits[cur_region][:count] = cur_count 
			end
		end
	end


	# Determine if the entire region of the given square has been mapped
	def handle_region cur_region
		cached_liaisons = $region.get_liaisons cur_region
		if cached_liaisons.nil? or cached_liaisons.empty?
			$logger.info "WARNING: region has no liaisons"
			return false
		end

		# Find a square within the given region
		square = nil
		liaison = cached_liaisons.values[0]
		if liaison.region != cur_region
			[ :N, :E, :S, :W].each do |dir|
				n = liaison.neighbor(dir)
				next if n.region.nil?
				next if n.water?

				if n.region == cur_region
					square = n
					break
				end
			end
		else
			square = liaison
		end

		if square.nil?
			$logger.info "WARNING: could not find square within region"
			return false
		end

		$logger.info "entered: #{ square }, region #{ square.region}"

		regions = []
		q = [ square ]
		done = []

		while not q.empty?
			sq = q.pop

			next if done.include? sq
			done << sq

			next if sq.water?

			if sq.region.nil?
				$logger.info { "#{ sq } has no region" }
				return false
			end

			if sq.region != cur_region
				regions << sq.region unless regions.include? sq.region
				next
			end


			[ :N, :E, :S, :W].each do |dir|
				q << sq.neighbor(dir)
			end
		end	

		# If you got this far, mapping is complete
		$logger.info "mapping region #{ cur_region } complete"

		if done.empty?
			$logger.info "WARNING: no points found in region"
			return false
		end

		sum_row = 0
		sum_col = 0
		count = 0
		done.each do |sq|
			sum_row += sq.row
			sum_col += sq.col
			count += 1
		end

		coord = [ sum_row/count, sum_col/count ]

		$logger.info { "Center region #{ cur_region }: #{ coord }; neigbor regions: #{ regions}" }

		add_exits cur_region, true, coord
		true
	end


	def add_exits cur_region, completed = false, coord = nil

		if not @exits[cur_region].nil?
			if !completed or @exits[cur_region][:completed]
				$logger.info {
					"#{ cur_region } already present in exits; completed: #{ @exits[cur_region][:completed] } ."
				}
				return 
			end
		end

		cached_liaisons = $region.get_liaisons cur_region
		if cached_liaisons.nil? or cached_liaisons.empty?
			$logger.info "WARNING: region has no liaisons"
			return false
		end

		exits = cached_liaisons.clone
		# ensure that exits are on the target region
		exits.clone.each_pair do |k,v|
			next if v.region == k

			have_hole = false
			[ :N, :E, :S, :W ].each do |dir|
				sq = v.neighbor dir
				next unless sq.land?


				if sq.region == k
					$logger.info { "Replacing exit #{ v } with #{ sq} " }
					exits[k] = sq

					# If hole is the only option, use it
					# But search further
					break unless sq.hole?
				end	
			end

			# Sanity check
			$logger.debug {
				raise "wrong region for exit point #{ exits[k] }!" if exits[k].region != k 
			}
		end
		
		@exits[cur_region] = {
			:exits  => exits
		}

		unless coord.nil?
			@exits[cur_region][:coord ] = coord
		end

		set_distance_count cur_region
		if completed
			@exits[cur_region][:completed ] = true
			analyze_regions
		end
	end


	def add_hill_region sq
		$logger.info "Adding region #{ sq.region } for square #{ sq }"

		@regions << sq.region
		get_region_liaisons sq.region
	end


	# 
	# Retrieve all liaisons from given region AND the known neighboring
	# regions
	def get_nearby_liaisons region, skip_regions
		$logger.info "entered"

		cached_liaisons = $region.get_liaisons region

		return [] if cached_liaisons.nil?


		liaisons = []

		cached_liaisons.each_pair do |k, v|
			next if skip_regions.include? k
			liaisons << v

			tmp = $region.get_liaisons k
			next if tmp.nil?

			tmp.each_pair do |k2,v2|
				next if skip_regions.include? k2
				liaisons << v2
			end
		end
		
		liaisons.uniq!

		$logger.info { "nearby liaisons for region #{ region }: #{ liaisons }" }
		liaisons
	end


	def get_region_liaisons region
		if  @complete_regions.include? region
			# This region has been handled to completion
			return
		else
			if handle_region region
				@complete_regions << region
			end

			# Do the liaisons one final time
		end

		ret = false

		cached_liaisons = $region.get_liaisons region

		unless cached_liaisons.nil?
			next_regions, liaisons = cached_liaisons.to_a.transpose

			# Add regions to active list
			next_regions.each do |r|
				@regions <<  r
				@regions -= @complete_regions
			end

			# Add liaisons to active list
			done = true
			liaisons.each do |l|
				next if @done_liaisons.include? l
				done = false

				unless @liaisons.include? l
					$logger.info "Adding #{ l } to liaisons list"

		
					# Added liaisons have the tendency to be grouped in a particular
					# region. If they are added linearly to the list, new ants all tend
					# to go in the same direction for an extended period, leaving other
					# directions unocuppied and therefor vulnerable.
					#
					# Following intended to shuffle the list to reduce this effect.
					if @liaisons.empty?
						@liaisons << l
					else
						@liaisons.insert rand( @liaisons.length ), l
					end
					#@liaisons.rotate!
					#@liaisons << l
				end
			end

			if done
				$logger.info "Completed border patrol for region #{ region }"

				$ai.my_ants.each do |a|
					liaisons.each do |l|
						if a.has_order :DEFEND, l
							tmp = next_liaison l
							unless tmp.nil?
								a.change_order tmp , :DEFEND
							else
								a.clear_order :DEFEND
							end
							break
						end
						#if a.has_order :GOTO, l
						#	a.clear_order :GOTO
						#	break
						#end
					end
				end
			end
		else
			$logger.info "No liaisons for region #{ region }"
		end


		if  @complete_regions.include? region
			@regions.delete region
		end

		ret
	end


	def action
		changed = false

		unless @regions.empty?
			changed = get_region_liaisons  @regions[0]
			@regions.rotate! 
		end

		$logger.info { "\n" +
			"have regions: #{ @regions.join(", ") }\n" +
			"Num completed regions: #{ @complete_regions.length }\n" +
			"have liaisons: #{ @liaisons.join(", ") }\n" +
			"last liaison: #{ @last_liaison }\n" +
			"num done liaisons: #{ @done_liaisons.length }"
		}

		changed
	end


	def select_exit_regions sq, skip_regions
		$logger.info "entered, sq #{sq}"

		exits = @exits[sq.region][:exits]

		ret = nil

		if exits.nil? or exits.empty?
			# bummer....
		elsif exits.length == 1
			ret = exits.keys
		else
			# Select directions to highest count number or nil numbers
			tmp = []
			highest = nil
			exits.keys.each do |k|
				if @exits[k].nil? or @exits[k][:count].nil?
					tmp << k
				else
					if highest.nil? or @exits[k][:count] > highest
						highest = @exits[k][:count]
					end
				end
			end

			$logger.info "tmp #{tmp}"

			unless highest.nil?
				exits.keys.each do |k|
					next if @exits[k].nil? or @exits[k][:count].nil?

					if @exits[k][:count] == highest
						tmp << k
					end
				end
			end

			$logger.info "tmp2 #{tmp}"

			if tmp.length == 1
				ret = tmp
			elsif tmp.empty?
				# bummer....pick anything
				ret = exits.keys
			else
				# See if we can go to a region we have not been before.
				tmp_keys = tmp - skip_regions
				$logger.info "tmp_keys #{tmp_keys}"

				if tmp_keys.empty?
					# bummer....pick anything
					ret = tmp
				else
					ret = tmp_keys
				end
			end
		end

		$logger.info "ret #{ ret }"
		ret
	end

	def next_liaison sq, skip_regions
		$logger.info "entered, sq #{sq}"

		add_exits sq.region

		ret = select_exit_regions sq, skip_regions

		k = sq.region
		last_select = @exits[k][:last_select]

		if ret.nil? or ret.empty?
			# Bummer....
			ret = nil
		elsif ret.length == 1
			# Go with the single option
			ret = @exits[k][:exits][ ret[0] ]

			unless last_select.nil?
				@exits[k].delete :last_select
			end
		else
			# Select a direction which was not previously selected at this region

			if last_select.nil? or not ret.include? last_select
				key = ret[0]
			else
				tmp = ret.rotate( ret.index( last_select ) + 1 )
				key = tmp[0]
			end

			ret = @exits[k][:exits][ key ]
			$logger.info "new last_select: #{ key }" 
			@exits[k][:last_select] = key
		end
		
		$logger.info "ret #{ ret }"
		ret
	end

	def next_liaison1 sq, skip_regions
		$logger.info "entered, sq #{sq}"

		lam = lambda do |list, sq|
			if not list.nil? and not list.empty?
				list.clone.each do |l|
					if l == sq
						$logger.info "Already there!"
						clear_liaison l
					else
						return l 
					end
				end
			end

			return nil
		end

		ret = nil

		# Only assign a liaison if the given square is in one of the completed regions
		if known_region sq.region

			unless @liaisons.empty?
				# Detect nearby active liaisons
				tmp1 = get_nearby_liaisons sq.region, skip_regions
				tmp = tmp1 & @liaisons

				$logger.info { "nearby active liaisons: #{ tmp }" }
				ret = lam.call tmp, sq

				if ret.nil? 
					# No nearby options found, just get the first
					ret = lam.call @liaisons, sq

					## Get a nearby liaison instead
					#ret = lam.call tmp1, sq
				end
			
				# Change the list order, even if we did not get the first item
				@liaisons.rotate!
			else
				redo_hills
			end

		end


		$logger.info "ret #{ ret }"
		ret
	end


	def redo_hills
		if @liaisons.empty?
			$logger.info "No border liaisons present; redoing from hills"
			$ai.hills.each_friend do |sq|
				add_hill_region sq
			end

			BorderPatrolFiber.add_list "go"
			true
		else
			false
		end
	end


	def known_region region
		@complete_regions.include? region or @regions.include? region
	end


	def clear_liaison sq
		if @liaisons.include? sq

			$logger.info "liaison #{ sq } cleared"
			@last_liaison = sq
			@liaisons.delete sq
			@done_liaisons << sq
			true
		end

		false
	end
end
