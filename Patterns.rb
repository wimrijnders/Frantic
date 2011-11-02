require 'prime'

class Hypothesis
	attr_accessor :name, :type, :orient, :num_players, :row_inc, :col_inc
	attr_accessor :negated, :supported, :good_matches

	def initialize name, type, orient, num_players, row_inc, col_inc
		@name, @type, @orient, @num_players, @row_inc, @col_inc = 
			name, type, orient, num_players, row_inc, col_inc

		@negated = nil
		@supported = nil
		@good_matches = 0
	end

	def to_s
		str = ""
		if name == :SLICE
			str << "[ #{ row_inc}, #{col_inc}]"
		end

		if good_matches > 0
			str << "; good matches: #{ good_matches }"
		end

		name.to_s + str
	end
end


class Patterns

	def add_square square
		@add_squares.push square
	end

	def initialize ai
		@add_squares = []
		@ai = ai
		@tests = []

		Thread.new do
			Thread.current[ :name ] = "Patterns"
			$logger.info "activated"

			@radius = ( ai.viewradius/Math.sqrt(2) ).to_i

			$logger.info "viewradius2: #{ ai.viewradius2 }"
			$logger.info "radius: #{ @radius }"

			init_tasks

			doing = true
			while doing
				$logger.info "waiting"
				sleep 0.2 while @add_squares.length == 0

				# Only handle last square added
				square = @add_squares.pop
				@add_squares.clear

				$logger.info { "Got square #{ square}" }
				show_field square

				match_tests square

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

	def init_tasks
		rows = ai.rows
		cols = ai.cols

		# NOTE: rotational symmetry also occurs! See h 4 2
		# TODO: analyze this special case

		if ( rows % 2) != 0 or ( cols %2 ) != 0 
			$logger.info "Uneven dimensions. Line symmetry not an option"
		else
			if rows == cols
				$logger.info "square board. Diagonal symmetry possible."

				@tests << Hypothesis.new( :DIAG_BLTR, :ONE, :mir90,  nil, 1, 1 )
				@tests << Hypothesis.new( :DIAG_TLBR, :ONE, :mir270, nil, -1, 1 )
			end

			@tests << Hypothesis.new( :HOR, :ONE, :mir0, nil, 1, 0 )
			@tests << Hypothesis.new( :VERT,:ONE, :mir180, nil, 0, 1 ) 
		end

		# slices always possible
		row_dims = factors_of rows

		# At least 2 players
		# assume not more than 16 players
		row_dims.delete_if { |r| r[0] < 2 or r[0] >= 16 }
		#logger.info { "Row dimensions possible values: #{ row_dims }" }

		col_dims = factors_of cols
		col_dims.delete_if { |r| r[0] < 2 or r[0] >= 16 }
		#$logger.info { "Col dimensions possible values: #{ col_dims }" }

		# Combine workable values
		dims = []
		col_tmp = col_dims.transpose
		row_dims.each do |r|
			index = col_tmp[0].index r[0]	

			unless index.nil?
				dims << ( r << col_tmp[1][index] )
			end
		end

		$logger.info { "Workable values: #{ dims }" }

		# Define the tests for slices
		dims.each  do |dim|
			# Coords in one direction may be multiples up to (not including) number of players
			(1...(dim[0])).each do | factor |
				@tests << Hypothesis.new( :SLICE, :ALL, :rot0, dim[0], dim[1], factor*dim[2] )
			end
		end

		$logger.info "done"
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


	def match_tests source
		@tests.each do |test|
			#$logger.info "Running test #{ test }"
			coord = [ 0, 0 ]

			total_count = 0
			match_count = 0
			fail_count  = 0


			max_count = 0
			if test.name == :SLICE
				max_count = test.num_players - 1
			else
				# For the life of me, I can not understand why I can't directly do
				# max_count = ai.rows -1

				# For diagonal symmetry, it is not necessary to test an entire diagonal line
				# over the whole surface. The question is, of course, how far DO you test without
				# prior knowledge.
				rows = ai.rows
				max_count = rows -1
			end

			1.upto( max_count) do
				coord[0] += test.row_inc
				coord[1] += test.col_inc

				total_count += 1

				target = source.rel coord	
				#$logger.info "Testing #{ target }"

				match = match_range source, target, test.orient

				if match.nil? 
					fail_count += 1

					break if test.type == :ALL
				else
					match_count += 1

					# signal 50% matches
					if match >= (2*radius+1)**2/2
						$logger.info { "Hypothesis #{ test } good match on #{ target}." }
						test.good_matches += 1
						show_field target
					end
				end
			end


			# Process the conclusions of the tests
			if test.type == :ALL
				if fail_count > 0
					$logger.info { "Hypothesis #{ test } negated." }
					test.negated = true
				elsif total_count == match_count
					#$logger.info { "Hypothesis #{ test } supported." }
					#test.supported = true
				end
			else # :ONE
				if match_count == 0 
					# NB: if you are on top of the symmetry line, following can happen as well
					# Same goes for when you are at the outer border of the symmetry region
					$logger.info { "Hypothesis #{ test } negated." }
					test.negated = true
				elsif match_count == 1
					$logger.info { "Hypothesis #{ test } totally supported." }
					test.supported = true
				else
					# Theoretically, it is possible that there are more matches, if there
					# is more symmetry in the map. For the time being, we consider this
					# extra test as pedantic, hoping that the sysops of the challenge don't 
					# come up with this idea.
					#
					# TODO: handle this case anyway
				end
			end
		end

		# clean up negated tasks
		@tests.delete_if { |t| t.negated === true }


		$logger.info { "Tests still in the running:\n\t#{ @tests.join( "\n\t") }" }
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
			
				match = match_range source, target, how
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
	# Count the number of true positive matches
	# test aborts if a true mismatch is encountered
	#
	def match_range sq1, sq2, how 
		matches = 0

		range = (-radius..radius)
		range.each do |row|
			range.each do |col|
				sq_a = sq1.rel [ row, col ]
				sq_b = sq2.rel target_coord( row, col, how )

				next if sq_a.region.nil? or sq_b.region.nil?

				if sq_a.water? == sq_b.water?
					matches += 1
				else
					return nil
				end

			end
		end

		matches
	end


	#
	# Example output:
	#
	#		p factors_of(4800) # => [[1, 4800], [2, 2400], ..., [4800, 1]]
	#
	# Source: http://stackoverflow.com/questions/3398159/all-divisors-of-a-given-number
	def factors_of(number)
		primes, powers = number.prime_division.transpose
		exponents = powers.map{|i| (0..i).to_a}
		divisors = exponents.shift.product(*exponents).map do |powers|
			primes.zip(powers).map{|prime, power| prime ** power}.inject(:*)
		end
		divisors.sort.map{|div| [div, number / div]}
	end
end
