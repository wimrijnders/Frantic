require 'prime'

class Hypothesis
	attr_accessor :parent, :name, :type, :orient, :num_players, :row_inc, :col_inc
	attr_accessor :negated, :supported, :good_matches

	@@ai = nil

	def initialize parent, name, type, orient, num_players, row_inc, col_inc
		@parent, @name, @type, @orient, @num_players, @row_inc, @col_inc = 
			parent, name, type, orient, num_players, row_inc, col_inc

		@negated = nil
		@supported = nil
		@good_matches = 0
	end

	def self.set_ai ai
		@@ai = ai
	end

	def to_s
		str = ""
		if good_matches > 0
			str << "; good matches: #{ good_matches }"
		end

		name.to_s + str
	end


	def test_match source
		# For the life of me, I can not understand why I can't directly do
		# max_count = ai.rows -1
		# TODO: test if this is still the case

		rows = ai.rows
		iterate source, rows - 1
	end

	private 

	def ai
		@@ai
	end

	def iterate source, max_count
		#$logger.info "Running test #{ self }"
		coord = [ 0, 0 ]

		total_count = 0
		match_count = 0
		fail_count  = 0

		1.upto( max_count) do
			coord[0] += row_inc
			coord[1] += col_inc

			total_count += 1

			target = source.rel coord	
			#$logger.info "Testing #{ target }"

			match = parent.match_range source, target, orient

			if match.nil? 
				fail_count += 1

				break if type == :ALL
			else
				match_count += 1

				# signal 50% matches
				if match >= (2*parent.radius+1)**2/2
					$logger.info { "Hypothesis #{ self } good match on #{ target}." }
					@good_matches += 1
					parent.show_field target
				end
			end
		end

		conclude fail_count, match_count, total_count
	end

	#
	# Process the conclusions of the test
	#
	def conclude fail_count, match_count, total_count
		if type == :ALL
			if fail_count > 0
				$logger.info { "Hypothesis #{ self } negated." }
				@negated = true
			elsif total_count == match_count
				#$logger.info { "Hypothesis #{ test } supported." }
				#@supported = true
			end
		else # :ONE
			if match_count == 0 
				# NB: if you are on top of the symmetry line, following can happen as well
				# Same goes for when you are at the outer border of the symmetry region
				$logger.info { "Hypothesis #{ self } negated." }
				@negated = true
			elsif match_count == 1
				$logger.info { "Hypothesis #{ self } totally supported." }
				@supported = true
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

end

class RotHypothesis < Hypothesis
	TEST_LIMIT = 100

	def initialize parent, name
		super parent, name, nil, nil, nil, nil, nil

		@total = ai.rows*ai.cols	

		row_offset = 0
		col_offset = 0
		if ai.rows % 2 == 0
			row_offset = 0.5
			$logger.info "Even rows; added 0.5 offset."
		end
		if ai.cols % 2 == 0
			col_offset = 0.5
			$logger.info "Even cols; added 0.5 offset."
		end
		

		@rot_points = []
		(0...ai.rows).each do |row|
			(0...ai.cols).each do |col|
				point = [ row + row_offset, col + col_offset ]

				@rot_points << point
			end
		end
	end

	def right d
		[ d.col, -d.row]
	end

	def right2 d
		[ -d.row, -d.col]
	end

	def left d
		[ -d.col, d.row]
	end


	def test_match source
		# Don't do them all at once, there are way too many
		# test_target takes too long per point ( about 20ms)
		start = 0
		final = -1
		if @rot_points.length > TEST_LIMIT
			start = rand( @rot_points.length - TEST_LIMIT )
			final = start - 1 + TEST_LIMIT
		end

		@skip_test = 0
		@rot_points[start..final].clone.each do |point|
			d = Distance.new( point, source )

			# Skip tests on possible border points; these are bound to fail
			if ( d.row.abs >= ( ai.rows/2 - parent.radius ) ) or
				( d.col.abs >= ( ai.cols/2 - parent.radius  ) )
				@skip_test += 1

				#$logger.info { "#{ source} possible border point for center #{ point}; skipping test" }
				next
			end

			do_test source, d, point
		end

		$logger.info { "Skipped #{ skip_test }/#{ TEST_LIMIT } on border tests for #{ source}" }

		@negated = true if @rot_points.length == 0
	end


	def to_s
		str = "; #{ @rot_points.length }/#{ @total }"

		if good_matches > 0
			str << "; good matches: #{ good_matches }"
		end

		name.to_s + str
	end

	private

	def test_target source, d, point, what
		if what == :rot90
			turn = right d	
		elsif what == :rot270
			turn = left d
		else
			# rot 180
			turn = right2 d
		end

		target = ai.map[ point[0] ][ point[1] ].rel  turn

		match = parent.match_range source, target, what
		if match.nil?
			#$logger.info { "#{ name }; point #{ point } negated." }
			@rot_points.delete point
			return false
		else
			# signal 50% matches
			if match >= (2*parent.radius+1)**2/2
				$logger.info { "Hypothesis #{ self } good match on #{ target}, center #{ point }." }
				@good_matches += 1
				parent.show_field target
			end
		end

		true
	end
end

class Rot90Hyp < RotHypothesis
	def initialize parent
		super parent, :ROT90
	end

	def do_test source, d, point
		return false unless test_target source, d, point, :rot90
		test_target source, d, point, :rot270
	end
end

class Rot180Hyp < RotHypothesis

	def initialize parent
		super parent, :ROT180
	end


	def do_test source, d, point
		test_target source, d, point, :rot180
	end
end


class DiagHyp < Hypothesis
	def initialize parent, name, type, orient, num_players, row_inc, col_inc
		super parent, name, type, orient, num_players, row_inc, col_inc
	end
end

class HorVertHyp < Hypothesis
	def initialize parent, name, type, orient, num_players, row_inc, col_inc
		super parent, name, type, orient, num_players, row_inc, col_inc
	end
end


class SliceHyp < Hypothesis
	def initialize parent, name, type, orient, num_players, row_inc, col_inc
		super parent, name, type, orient, num_players, row_inc, col_inc
	end

	def test_match source
		iterate source, num_players - 1
	end

	def to_s
		str = "[ #{ row_inc}, #{col_inc}]"

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
		Hypothesis.set_ai ai

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

	def radius 
		@radius	
	end


	private 

	def ai
		@ai
	end

	def init_tasks
		rows = ai.rows
		cols = ai.cols

		# NOTE: rotational symmetry also occurs! See h 4 2
		# TODO: analyze this special case

		if rows == cols
			$logger.info "square board. Diagonal/rotational symmetry possible."

			@tests << Rot90Hyp.new( self )
			@tests << DiagHyp.new( self, :DIAG_BLTR, :ONE, :mir90,  nil, 1, 1 )
			@tests << DiagHyp.new( self, :DIAG_TLBR, :ONE, :mir270, nil, -1, 1 )
		end

		@tests << Rot180Hyp.new( self )
		@tests << HorVertHyp.new( self, :HOR, :ONE, :mir0, nil, 1, 0 )
		@tests << HorVertHyp.new( self, :VERT,:ONE, :mir180, nil, 0, 1 ) 

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
				@tests << SliceHyp.new( self, :SLICE, :ALL, :rot0, dim[0], dim[1], factor*dim[2] )
			end
		end

		$logger.info "done"
	end



	def match_tests source
		@tests.each do |test|
			test.test_match source
		end

		# clean up negated tasks
		@tests.delete_if { |t| t.negated === true }
		@tests.compact!

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
