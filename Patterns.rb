class Patterns

	def add_square square
		@add_squares.push square
	end

	def initialize ai
		@add_squares = []
		@ai = ai

		Thread.new do
			Thread.current[ :name ] = "Patterns"
			$logger.info "activated"

			@radius = ( ai.viewradius/Math.sqrt(2) ).to_i

			$logger.info "viewradius2: #{ ai.viewradius2 }"
			$logger.info "radius: #{ @radius }"

			doing = true
			while doing
				$logger.info "waiting"
				sleep 0.2 while @add_squares.length == 0

				# Only handle last square added
				square = @add_squares.pop
				@add_squares.clear

				$logger.info { "Got square #{ square}" }
				show_field square

				match square

			end

			$logger.info "closing down."
		end
	end

	private 

	def ai
		@ai
	end

	def radius 
		@radius	
	end


	def show_field square
		str = ""
		(-radius).upto(radius) do |row|
			(-radius).upto(radius) do |col|

				sq = square.rel [ row, col ]

				str << if sq.region.nil? 
					"?"
				elsif sq.water?
					"W"
				else
					"_"
				end

			end

			str << "\n"
		end

		$logger.info "pattern region:\n#{ str }" 
	end


	def match source
		(0...ai.rows).each do |row|
			(0...ai.cols).each do |col|
				# We can not exclude overlap of the entire search regions
				# here, due to possible symmetry borders within the search
				# region
				if row == source.row and col == source.col
					next
				end

				target = ai.map[ row ][ col ]

				match_square( source, target) do | how, match |
					$logger.info "Match result: orientation #{ how }, matches #{ match }"
					$logger.info { "target #{ target }" }
					show_field target
				end
			end
		end
	end


	def match_square sq1, sq2
		[ :rot0, :rot90, :rot180, :rot270,
		  :mir0, :mir90, :mir180, :mir270 ].each do |how|

			match = match_range sq1, sq2, how

			next if match.nil?

			# Let's say that 25% of region should match
			if match >= (2*radius+1)**2/4
				yield how, match
			end
		end
	end

	def target_coord row, col, how
		case how
		when :rot0
			[ row, col ]
		when :rot90
			[ -col, row ]
		when :rot180
			[ -row, -col ]
		when :rot270
			[ col, -row ]
		when :mir0
			[ -row, col ]
		when :mir90
			[ -col, -row ]
		when :mir180
			[ row, -col ]
		when :mir270
			[ col, row ]
		end
	end

	#
	# Count the number of positive matches
	# test aborts if a positive mismatch is encountered
	#
	def match_range sq1, sq2, how 
		matches = 0
		water   = 0

		range = (-radius..radius)
		range.each do |row|
			range.each do |col|
				sq_a = sq1.rel [ row, col ]
				sq_b = sq2.rel target_coord( row, col, how )

				next if sq_a.region.nil? or sq_b.region.nil?

				if sq_a.water? == sq_b.water?
					matches += 1
					water   += 1 if sq_a.water?
				else
					return nil
				end

			end
		end

		# don't return a match if no water found
		if water == 0
			nil	
		else
			matches
		end
	end
end
