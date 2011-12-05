class BorderPatrol
	def initialize
		@complete_regions = []

		@regions = []
		@liaisons = []
		@done_liaisons = []
		@last_liaison = nil
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

		true
	end


	def add_hill_region sq
		$logger.info "Adding region #{ sq.region } for square #{ sq }"

		@regions << sq.region
		get_region_liaisons sq.region
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

					@liaisons << l
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

		$logger.info "have regions: #{ @regions.join(", ") }"
		$logger.info "Num completed regions: #{ @complete_regions.length }"
		$logger.info "have liaisons: #{ @liaisons.join(", ") }"
		$logger.info "last liaison: #{ @last_liaison }"
		$logger.info "num done liaisons: #{ @done_liaisons.length }"

		changed
	end


	def next_liaison sq
		$logger.info "entered, sq #{sq}"

		ret = nil

		# Only assign a liaison if the given square is in one of the completed regions
		if known_region sq.region

			unless @liaisons.empty?
					ret = @liaisons[0]
					@liaisons.rotate!

if false
				# This takes painfully long. TODO: find better solution
	
				# Find nearest border liaison to given square
				nearest = $pointcache.get_sorted sq, @liaisons, true

				if nearest
					$logger.info { "Selecting nearest border liaison #{ nearest[0][0] }" }
					ret = nearest[0][0]
				else
					ret = @liaisons[0]
					@liaisons.rotate!
				end
end
			else
				#ret = @last_liaison
				redo_hills
			end
		end

		$logger.info "ret #{ ret }"
		ret
	end

	# TODO: apparently not called any more
	def redo_hills
		if @liaisons.empty?
			$logger.info "No border liaisons present; redoing from hills"
			$ai.hills.each_friend do |sq|
				add_hill_region sq
			end

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

		#redo_hills
		false
	end
end
