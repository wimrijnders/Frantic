class Exits

	attr_accessor :region, :done
	
	def initialize parent, region, exits, coord, completed
		@parent = parent
		@region = region
		@exits = exits 
		@coord = coord
		@completed = completed
	
		set_distance_count
	end

	def exits; @exits; end
	def count; @count; end
	def completed; @completed; end

	def last_select ret
		if @last_select.nil? or not ret.include? @last_select
			key = ret[0]
		else
			tmp = ret.rotate( ret.index( @last_select ) + 1 )
			key = tmp[0]
		end

		$logger.info "new last_select: #{ key }" 
		@last_select = key

		@exits[ key ]
	end

	def clear_last_select
		@last_select = nil
	end

	def select_exit_regions skip_regions

		ret = nil

		if exits.nil? or exits.empty?
			# bummer....
		elsif exits.length == 1
			ret = exits.keys
		else
			# Select directions to highest count number or nil numbers
			tmp = []
			highest = nil
			each_exit do |k, x|
				if x.nil? or x.count.nil?
					tmp << k
				else
					if highest.nil? or x.count > highest
						highest = x.count
					end
				end
			end

			$logger.info "tmp #{tmp}"

			unless highest.nil?
				each_exit do |k, x|
					next if x.nil? or x.count.nil?

					if x.count == highest
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

		if ret.nil? or ret.empty?
			# Bummer....
			ret = nil
		elsif ret.length == 1
			# Go with the single option
			ret = exits[ ret[0] ]
			clear_last_select
		else
			# Select a direction which was not previously selected at this region
			ret = last_select ret
		end

		$logger.info "ret #{ ret }"
		ret
	end


	def set_distance_count
		return true	unless @count.nil?

		if $ai.hills.my_hill_region? @region
			@count = 0
		else
			# get the lowest count from the surrounding regions

			lowest = nil
			each_exit do |r, item|
				next if item.nil?
				next if item.count.nil?

				if lowest.nil? or item.count < lowest
					lowest = item.count
				end
			end

			unless lowest.nil?
				cur_count = lowest + 1
				@count = cur_count 
			end
		end

		@count.nil?
	end


	def show
		str = ""

		if done and exits.length == 1
			str << "   #{ region } => { #{ count }, #{ exits }   }\n"
		else
			if done
				str << "done"
			elsif @completed
				str << "completed"
			end

			#str << "coord #{ @coord }
			str << "
      exits: #{ @exits }
      count: #{ @count }
"

			unless @last_select.nil?
				str << "      last_select: #{ @last_select }\n"
			end

			"   #{ region } => { #{ str }   }\n"
		end

	end

	def counts 
		ret = Hash.new { |hash, key| hash[key] = [] }

		each_exit do |k, x|
			if x.nil? or x.count.nil?
				ret[nil] << k
			else
				ret[ x.count ] << k
			end
		end

		$logger.info { "ret #{ ret }" }

		ret
	end

	def delete_exit to
		if exits.nil? or count.nil?
			$logger.info "not enough info; not deleting"
			return false
		end

		return false unless exits.include? to

		c = counts
		lowest = nil
		c.keys.each { |v|
			if not v.nil? and (  lowest.nil? or v < lowest )
				lowest = v
			end
		}

		$logger.info "lowest #{ lowest }"
		if lowest.nil?
			$logger.info "Can't determine lowest; not deleting"
			return false
		end

		$logger.info { "region #{ @region } count #{ count } - lowest #{ lowest }" }

		if lowest < count

			if c[lowest].include? to and c[lowest].length == 1
				$logger.info "not removing last lowest link"
				return false
			end
		else
			# This happens in hill regions
			if exits.length == 1
				$logger.info { "Only one exit left for #{ @region }, not deleting" }
				return false
			end
		end

		exits.delete to 

		true
	end

	def delete_exit_redo to
		if delete_exit to
			# Exits changed, need to redo

			if done
				$logger.info "Redoing analysis for region #{ @region }"
				analyze_region
			end
		end
	end

	def remove_from_exits
		each_exit do |k, x|
			x.delete_exit_redo @region
		end
	end

	def hilo_counts

		highest = nil
		lowest = nil

		each_exit do |r, item|

			# If item or count not present, can not do this check
			if item.nil?
				return [nil, nil]
			end

			count = item.count
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


	def each_exit
		@exits.each_key do |k|
			yield k, @parent.exits[k]
		end
	end


	# Pre: all neighbors are top items in the exits hash
	def analyze_region
		# It possible that count has not been set, when
		# given region is not connected to a hill region.
		# Keep on retrying till we got it
		return unless set_distance_count
		return unless all_neighbors_present

		$logger.info "entered, #{ @region }"

		if exits.length == 1
			# Current region is a dead end
			# always remove from neighbor. 
			$logger.info "#{ @region } dead end."
			remove_from_exits
		end

		highest, lowest = hilo_counts

		if highest.nil? 
			# Perhaps this always goes well; not sure, leaving it in.
			$logger.info "can't complete analysis for #{ @region }; retrying later on"
			return
		end

		if highest < count
			# There are no higher exits; this is effectively a dead end
			$logger.info "Reached local max at #{ @region }"
			remove_from_exits
		elsif highest == count
			# Cut ties if these regions have no higher neighbor
			each_exit do |r, item|
				next unless item.count == highest

				hi, lo = item.hilo_counts
		
				if hi.nil? 
					$logger.info "can't complete analysis for #{ @region } 2; retrying later on"
					return
				end

				if hi <= highest
					$logger.info "#{ @region } neighbor #{ r } has no higher count than #{ highest }; cutting ties"

					delete_exit r
					item.delete_exit_redo @region
				end
			end
		end	


		# Sanity check; exit(s) we're going to,
		# should have an exit to a different region
		$logger.debug {
			break if exits.length > 1

			each_exit do |k, v|
				next if v.nil?

				tmp = v.exits.keys - [ @region]
				if tmp.length == 0
					raise "no other exits from #{ @region } through #{k}"
				end
			end
		}

		@done = true
	end


	def all_neighbors_present 
		each_exit do |k, x|
			return false if x.nil?

			# Combined isolated regions can have this. 
			if x.count.nil?
				$logger.info "WARNING: region #{ k } has no count."
				return false
			end
		end

		true
	end

end


class ExitsList

	def initialize
		@exits = {}
	end

	def add region, coord = nil, completed = false

		x = @exits[region]
		if not x.nil?
			if !completed or x.completed
				$logger.info {
					"#{ region } already present in exits; completed: #{ @exits[region].completed } ."
				}
				return 
			end
		end

		cached_liaisons = $region.get_liaisons region
		if cached_liaisons.nil? or cached_liaisons.empty?
			$logger.info "WARNING: region has no liaisons"
			return false
		end

		liaisons = cached_liaisons.clone
		# ensure that exits are on the target region
		liaisons.clone.each_pair do |k,v|
			next if v.region == k

			have_hole = false
			[ :N, :E, :S, :W ].each do |dir|
				sq = v.neighbor dir
				next unless sq.land?


				if sq.region == k
					$logger.info { "Replacing exit #{ v } with #{ sq} " }
					liaisons[k] = sq

					# If hole is the only option, use it
					# But search further
					break unless sq.hole?
				end	
			end

			# Sanity check
			$logger.debug {
				raise "wrong region for exit point #{ liaisons[k] }!" if liaisons[k].region != k 
			}
		end

		$logger.info "liaisons #{ liaisons }"
	

		@exits[region ] = Exits.new self, region, liaisons, coord, completed
		analyze_regions
	end


	def exits; @exits; end

	def [] key
		@exits[ key ]
	end


	def analyze_regions
		# Update counts
		@exits.each_value do |v|
			next if v.done
			v.analyze_region
		end

		show_exits
	end


	def show_exits
		$logger.info {
			str = ""

			@exits.each_value do |v|
				str << v.show
			end
			"exits: {\n#{ str }}"
		}
	end


	def select_exit_regions sq, skip_regions
		$logger.info "entered, sq #{sq}"

		ret = @exits[sq.region].select_exit_regions skip_regions

		$logger.info "ret #{ ret }"
		ret
	end

end


class BorderPatrol
	def initialize
		@complete_regions = []

		@regions = []
		@liaisons = []
		@done_liaisons = []
		@last_liaison = nil

		@exits = ExitsList.new
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

		@exits.add cur_region, coord, true
		true
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
			"Num completed regions: #{ @complete_regions.length }\n" #+
			#"have liaisons: #{ @liaisons.join(", ") }\n" +
			#"last liaison: #{ @last_liaison }\n" +
			#"num done liaisons: #{ @done_liaisons.length }"
		}

		changed
	end




	def next_liaison sq, skip_regions
		$logger.info "entered, sq #{sq}"

		@exits.add sq.region

		ret = @exits.select_exit_regions sq, skip_regions

		
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
