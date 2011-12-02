class BorderPatrol
	def initialize
		@regions = []
		@done_regions = []
		@liaisons = []
		@done_liaisons = []
		@last_liaison = nil
	end

	def add_hill_region sq
		$logger.info "Adding region #{ sq.region } for square #{ sq }"

		@regions << sq.region
	end

	def get_region_liaisons region
		ret = false

		cached_liaisons = $region.get_liaisons region

		unless cached_liaisons.nil?
			next_regions, liaisons = cached_liaisons.to_a.transpose

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

				# move on to next region
				next_regions.each { |r|
					if not @regions.include? r and not @done_regions.include? r
						# Regions have changed, signal that we need to reloop
						ret = true
						@regions << r
					end
				}
				@regions.delete region
				@done_regions << region

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

		ret
	end


	def action
		changed = false

		unless @regions.empty?
			changed = get_region_liaisons  @regions[0]
			@regions.rotate! 
		end

		$logger.info "have regions: #{ @regions.join(", ") }"
		$logger.info "Num done regions: #{ @done_regions.length }"
		$logger.info "have liaisons: #{ @liaisons.join(", ") }"
		$logger.info "last liaison: #{ @last_liaison }"
		$logger.info "have done liaisons: #{ @done_liaisons.join(", ") }"

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
			else
				ret = @last_liaison
			end
		end

		$logger.info "ret #{ ret }"
		ret
	end


	def known_region region
		@done_regions.include? region or @regions.include? region
	end


	def clear_liaison sq
		return unless @liaisons.include? sq

		$logger.info "liaison #{ sq } cleared"
		@last_liaison = sq
		@liaisons.delete sq
		@done_liaisons << sq
	end
end
