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
	def coord; @coord; end

	def last_select ret
		if @last_select.nil? or
			ret.length == 1 or
			not ret.include? @last_select

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
		return nil if exits.nil? or exits.empty?

		if exits.length == 1
			clear_last_select
			return exits.values[ 0 ]
		end

		unexplored = []
		explored = []
		each_exit do |k, x|
			if x.nil? or x.count.nil?
				unexplored << k
			else
				explored << k
			end
		end

		$logger.info "keys #{ exits.keys }"
		$logger.info "skip_regions #{skip_regions}"
		hi, lo = hilo_counts
		highest = []
		lowest  = []
		explored.each do |k|
			x = @parent.exits[k]

			highest << x.region if not hi.nil? and  x.count == hi
			lowest  << x.region if not lo.nil? and  x.count == lo
		end


		# Go to regions we haven't been before
		tmp_keys = exits.keys - skip_regions
		if tmp_keys.empty?

			# Backtrack to lowest
			unless lowest.empty?
				$logger.info "lowest #{ lowest }"
				return last_select lowest
			end

			$logger.info "doing all"
			return last_select exits.keys
		elsif tmp_keys.length == 1
			clear_last_select
			return exits[ tmp_keys[0] ]
		end

		# If you have a choice, try to differentiate 



		# Go to unexplored regions
		unexplored &= tmp_keys
		unless unexplored.empty?
			$logger.info "unexplored #{unexplored}"
			return last_select unexplored
		end

		# Go to highest count
		highest &= tmp_keys
		unless highest.empty?
			$logger.info "highest #{ highest }"
			return last_select highest
		end


		# Never mind; do them all
		$logger.info "do all selected"
		return last_select tmp_keys
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

			#if done
				$logger.info "Redoing analysis for region #{ @region }"
				@parent.add_analyze self
			#end
		end
	end

	def remove_from_exits
		each_exit do |k, x|
			x.delete_exit_redo @region
		end
	end

	def peak?
		hi, lo = hilo_counts

		!hi.nil? and count > hi #and !@exits.length == 1
	end

	def hilo_counts
		highest = nil
		lowest = nil

		each_exit do |r, item|

			# If item or count not present, can not do this check
			if item.nil?
				return [nil, nil]
			end

			this_count = item.count
			if this_count.nil?
				return [nil, nil]
			end

			if lowest.nil? or this_count < lowest
				lowest = this_count
			end

			if highest.nil? or this_count > highest
				highest = this_count
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
if false
		#elsif highest == count
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
		end	

		# Final cleanup; current region could have become
		# a dead end after previous actions
		if exits.length == 1
			# Current region is a dead end
			# always remove from neighbor. 
			$logger.info "#{ @region } dead end."
			remove_from_exits
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


			# Only do completed regions or better
			return false unless x.done or x.completed

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
		@analyze_queue = []
	end


	def add region, coord = nil, completed = false

		x = @exits[region]
		if not x.nil?
			#if !completed or x.completed
			if x.completed
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
		liaisons.clone.each_pair do | to, liaison|
			liaisons[to] = exit_on_target liaison,to 
		end

		$logger.info "liaisons #{ liaisons }"
	

		@exits[region ] = Exits.new self, region, liaisons, coord, completed
		analyze_regions
	end


	def exits; @exits; end

	def [] key
		@exits[ key ]
	end


	def add_analyze v
		@analyze_queue << v
	end

	def analyze_regions
		$logger.info { "entered, #{ @analyze_queue.length } items in queue" }

		# Order important, take from start of queue
		while ( v = @analyze_queue.shift )
			# Don't check done here, we are redoing
			v.analyze_region
		end

		$logger.info { "analyze queue done" }

		@exits.each_value do |v|
			next if v.done
			v.analyze_region
		end

		show_exits
	end


	def show_exits
		unless Fiber.current?
			$logger.info {
				str = ""

				@exits.each_value do |v|
					str << v.show
				end
				"exits: {\n#{ str }}"
			}
		end
	end


	def select_exit_regions sq, skip_regions
		$logger.info "entered, sq #{sq}"

		return nil if @exits[sq.region].nil?

		ret = @exits[sq.region].select_exit_regions skip_regions

		$logger.info "ret #{ ret }"
		ret
	end


	def exit_on_target liaison, to
		return liaison  if liaison.region == to 

		have_hole = false
		[ :N, :E, :S, :W ].each do |dir|
			sq = liaison.neighbor dir
			next unless sq.land?


			if sq.region ==to 
				$logger.info { "Replacing exit #{ liaison } with #{ sq} " }
				liaison = sq

				# If hole is the only option, use it
				# But search further
				break unless sq.hole?
			end	
		end

		# Sanity check
		$logger.debug {
			raise "wrong region for exit point #{ liaison }!" if liaison.region != to 
		}

		liaison
	end 

	def is_peak region
		max = nil
		item = nil
		@exits.each_pair do | k, v |
			return false if not v.done

			# Select the highest done item
			if max.nil? or ( not v.count.nil? and v.count >= max )
				max = v.count

				if v.done
					item = v
				end
			end
		end

		( not item.nil? and max == item.count and region == item.region )
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

		@regions << sq.region unless @regions.include? sq.region
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
			return false
		end

		return false unless handle_region region

		@complete_regions << region

		# Do the liaisons one final time

		ret = false

		cached_liaisons = $region.get_liaisons region

		unless cached_liaisons.nil?
			#next_regions, liaisons = cached_liaisons.to_a.transpose
			next_regions = []
			liaisons = []
			cached_liaisons.each_pair do |to,liaison|
				next_regions << to 

				# Add adjusted liaisons for each bordering region 
				# Note that these are actually double now
				liaisons << @exits.exit_on_target( liaison, to  )
				liaisons << @exits.exit_on_target( liaison, region )
			end

			# Add regions to active list
			next_regions.each do |r|
				@regions <<  r
			end
			@regions.uniq!
			@regions -= @complete_regions

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

		@regions.clone.each do |r|
			changed = true if  get_region_liaisons  @regions[0]
			Fiber.yield
		end

		#unless @regions.empty?
		#	changed = get_region_liaisons  @regions[0]
		#	@regions.rotate! 
		#end

		if changed
		$logger.info { "\n" +
			"have regions: #{ @regions.join(", ") }\n" +
			"Num completed regions: #{ @complete_regions.length }\n" +
			#"have liaisons: #{ @liaisons.join(", ") }\n" +
			"have #{ @liaisons.length } liaisons\n" +
			"last liaison: #{ @last_liaison }\n" +
			"num done liaisons: #{ @done_liaisons.length }"
		}
		end

		changed
	end




	$done_peak = false
	def next_liaison sq, skip_regions
		$logger.info "entered, sq #{sq}"

		@exits.add sq.region
		ret = next_liaison1 sq, skip_regions

if false
		if @exits.is_peak sq.region
			$logger.info "#{ sq} is on peak region; changing strategy"
			$done_peak = true
		end

		if $done_peak
			ret = next_liaison1 sq, skip_regions
		else
			ret = @exits.select_exit_regions sq, skip_regions
		end
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

	def get_center  region
		if @exits[region].nil?
			nil
		else
			tmp = @exits[region].coord
			if tmp.nil?
				nil
			else
				Square.coord_to_square tmp
			end
		end
	end

	def num_exits region
		item = @exits[region]

		return 0 if item.nil?

		item.exits.length
	end
end
