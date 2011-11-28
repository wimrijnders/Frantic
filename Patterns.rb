require 'prime'

class Hypothesis
	CONFIRM_LIMIT = 10

	attr_accessor :parent, :name, :type, :orient, :num_players, :row_inc, :col_inc
	attr_accessor :negated, :supported, :good_matches, :confirmed, :complete

	@@ai = nil

	def initialize parent, name, type, orient, num_players, row_inc, col_inc
		@parent, @name, @type, @orient, @num_players, @row_inc, @col_inc = 
			parent, name, type, orient, num_players, row_inc, col_inc

		@negated = nil
		@supported = nil
		@good_matches = 0
		@symmetry_items = []
		@confirmed = false

		@complete = false
	end

	def symmetry_item
		#$logger.info "entered"

		@symmetry_items.each do |s|
			return s[0] if s[1] >= CONFIRM_LIMIT
		end

		nil
	end

	def self.set_ai ai
		@@ai = ai
	end

	def to_s
		name.to_s
	end

	def info
		str = ""
		if @confirmed
			str << "; Confirmed"
		elsif good_matches > 0
			str << "; matches: #{ good_matches }"
		end

		if @symmetry_items.length > 0
			str << "; symmetry lines/points: #{ @symmetry_items }"
		end

		to_s + str
	end


	def test_match source
		# For the life of me, I can not understand why I can't directly do
		# max_count = ai.rows -1
		# TODO: test if this is still the case

		rows = ai.rows
		iterate source, rows - 1
	end


	def confirm
		return if @symmetry_items.length == 0

		$logger.info "entered"

		# Generate a couple of random test points
		# Already mapped points are used, because otherwise the matching will take too long
		points = pick_done_regions 
		$logger.info { "Test points: #{ points }" }


		@symmetry_items.clone.each do |sym|
			points.each do |point|
				result = test_sym sym[0], point

				if result.nil?
					$logger.info "line/point #{ sym[0] } negated."
					@symmetry_items.delete sym
					break # to outer loop
				elsif result
					#$logger.info "Confirmation!"
					sym[1] += 1
				end
			end

			# Final confirmation
			if sym[1] >= CONFIRM_LIMIT
				@confirmed = true
				@symmetry_items = [ sym ]
				break
			end
		end
	end

	def get_source_targets source
		targets = get_targets source, self.symmetry_item, name

		# add direction info
		case self.name
		when :DIAG_TLBR
			[[ targets[0], :mir90 ]]
		when :DIAG_BLTR
			[[ targets[0], :mir270 ]]
		when :SLICE
			targets.collect { |t| [ t, :rot0] }
		when :HOR
			[[ targets[0], :mir0 ]]
		when :VERT
			[[ targets[0], :mir180 ]]
		when :ROT90
			[[ targets[0], :rot90 ], [ targets[0], :rot270 ]]
		when :ROT180
			[[ targets[0], :rot180 ]]
		end
			
	end

	private 

	# Source: http://snippets.dzone.com/posts/show/2087 (javascript)
	def checkIntersection line1, line2
		#$logger.info "entered; line1 #{ line1 }, line2 #{ line2 }"

		# Internally, lines are defined by two points on the line	
		lineAx1 = line1[0][0]
		lineAy1 = line1[0][1]
		lineAx2 = lineAx1 + line1[1][0]
		lineAy2 = lineAy1 + line1[1][1]

		lineBx1 = line2[0][0]
		lineBy1 = line2[0][1]
		lineBx2 = lineBx1 + line2[1][0]
		lineBy2 = lineBy1 + line2[1][1]

		ret = [ 0, 0 ]
	
		if lineAx2 == lineAx1
	    	bM = (lineBy2-lineBy1)/(lineBx2-lineBx1)
	    	bB = lineBy2-bM*lineBx2
	
	    	x = lineAx1
	    	ret = [ x, bM*x + bB ]
	  	elsif lineBx2 == lineBx1
	    	aM = (lineAy2-lineAy1)/(lineAx2-lineAx1)
	    	aB = lineAy2-aM*lineAx2
	
	    	x = lineBx1
			ret = [ x, aM*x + aB ]
		else
		    aM = (lineAy2-lineAy1)/(lineAx2-lineAx1)
			bM = (lineBy2-lineBy1)/(lineBx2-lineBx1)
			aB = lineAy2-aM*lineAx2
			bB = lineBy2-bM*lineBx2
	
			x = [ ((bB-aB)/(aM-bM)),0].max
			ret = [ x, aM*x + aB ]
		end
	
		#$logger.info { "#{ line1}, #{ line2} intersection at #{ ret } " }
		ret
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

	def get_targets source, sym, which
		targets = []

		if sym[0].kind_of? Array
			# Mirror over line - this works for all line symmetries
			# param 'which' not used here

			# Test line symmetry
			coeff  = sym[1]
			coeff2 = [ coeff[1], -coeff[0] ] 

			intersect = checkIntersection sym, [ [ source.row, source.col], coeff2]
			diff = [ source.row - intersect[0], source.col - intersect[1] ]

			targets << ai.map[ (intersect[0] - diff[0] ) % ai.rows ][ ( intersect[1] - diff[1]) % ai.cols ]
		elsif which == :ROT90 
			# rot90
			d = Distance.get sym, source
			turn = right d	
			coord = [ sym[0] + turn[0], sym[1] + turn[1] ]
			targets << ai.map[ coord[0] % ai.rows ][ coord[1] % ai.cols ]
		
			# rot270
			turn = left d
			coord = [ sym[0] + turn[0], sym[1] + turn[1] ]
			targets << ai.map[ coord[0] % ai.rows ][ coord[1] % ai.cols ]
		elsif which == :ROT180
			# rot 180
			d = Distance.get sym, source
			turn = right2 d
			coord = [ sym[0] + turn[0], sym[1] + turn[1] ]
			targets << ai.map[ coord[0] % ai.rows ][ coord[1] % ai.cols ]
		elsif which == :SLICE
			point = [ (source.row + sym[0] ) % ai.rows, ( source.col + sym[1] ) % ai.cols ]

			# Iterate until we reach the original source again
			while !( point[0] == source.row and point[1] == source.col )
				targets << ai.map[ point[0] ][ point[1] ]

				point = [ (point[0] + sym[0] ) % ai.rows, ( point[1] + sym[1] ) % ai.cols ]
			end

		else
			raise "get_targets unknown hypothesis name"
		end

		targets
	end


	def test_sym sym, point
		$logger.info "entered"

		targets = get_targets point, sym, orient

		$logger.info "Entering match_square #{ point}, #{ targets[0] }, #{ orient }"
		match = parent.match_range point, targets[0], orient

		return nil if match.nil?

		detect_good_match match, targets[0]
	end

	def ai
		@@ai
	end

	#
	# Randomly pick a number of done_region points for 
	# confirmation testing
	#
	def pick_done_regions
		$logger.info "entered"

		list = []
		(0...ai.rows).each do |row|
			(0...ai.cols).each do |col|
				sq = ai.map[row][col]
				list << sq if sq.done_region
			end
		end

		indexes = []
		while indexes.length < 10 and indexes.length < list.length
			n = rand( list.length )
			indexes << n unless indexes.include? n
		end

		out = []
		indexes.each {|i| out << list[i] }

		out
	end


	def detect_good_match match, target
		# signal 50% matches
		if match >= (2*parent.radius+1)**2/2
			$logger.info { "Hypothesis #{ self } good match on #{ target}." }
			@good_matches += 1
			parent.show_field target
			true
		else
			false
		end
	end


	def iterate source, max_count
		#$logger.info "Running test #{ self }"
		coord = [ 0, 0 ]

		total_count = 0
		match_count = 0
		fail_count  = 0

		1.upto( max_count) do
			# Be a good citizen
			Fiber.yield

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

				if detect_good_match match, target

					item = nil
					if self.is_a? SliceHyp
						# Good matches are offsets
						item = [ row_inc, col_inc ] 
				
						index = @symmetry_items.index { |n| n[0] == item } 
						unless index.nil? 
							$logger.info "Symmetry item offset #{ item } already present."
						else
							@symmetry_items << [ item, 0]
						end
					else
						# Good matches for this category are lines

						tmp_coord  =  [
							( (source.row + target.row)*1.0/2 ) % ai.rows,  
							( (source.col + target.col)*1.0/2 ) % ai.cols
						]
						$logger.info "coord: #{ tmp_coord }"

						# First element is coordinate, second is coefficient.
						# note that coeff is rotated 90%
						item = [ tmp_coord, [ col_inc, -row_inc]  ] 

						index = @symmetry_items.index { |n|
							compare_lines( n[0], item )
						} 
						unless index.nil? 
							$logger.info "Symmetry item line #{ item } already present."
						else
							$logger.info "Symmetry item line #{ item } not present."
							@symmetry_items << [ item, 0 ]
						end
					end
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


	def compare_lines line1, line2
		$logger.info "entered"

		# Lines should be at least in same orientation
		return false if line1[1] != line2[1]

		# hor/vert lines
		return ( line1[0][1] == line2[0][1] )  if line1[1][1] == 0 
		return ( line1[0][0] == line2[0][0] ) if line1[1][0] == 0 

		# Same direction, check if point of line2 is on line1
		(line2[0][0] - line1[0][0]) / line1[1][0] == 
		   (line2[0][1] - line1[0][1]) / line1[1][1]  
	end
end


class RotHypothesis < Hypothesis
	TEST_LIMIT = 50

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



	def test_match source
		# Don't do them all at once, there are way too many
		# test_target takes too long per point ( about 20ms)
		start = 0
		final = -1
		if @rot_points.length > TEST_LIMIT
			start = rand( @rot_points.length - TEST_LIMIT )
			final = start - 1 + TEST_LIMIT
		end

		@rot_points[start..final].clone.each do |point|
			d = Distance.get( point, source )

			do_test source, d, point
		end

		@negated = true if @rot_points.length == 0
	end


	def info
		str = ""
		unless @confirmed
			str = "; #{ @rot_points.length }/#{ @total }"
		end
		super + str
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

		coord  = ai.normalize point[0] + turn[0], point[1] + turn[1]
		target = ai.map[ coord[0] ][ coord[1] ]

		match = parent.match_range source, target, what
		if match.nil?
			#$logger.info { "#{ name }; point #{ point } negated." }

			@rot_points.delete point
			return false
		else
			if detect_good_match match, target
				# Good matches for this category are points

				index = @symmetry_items.index { |n| n[0] == point } 
				unless index.nil?
					$logger.info "Symmetry item #{ point } already present."
				else
					@symmetry_items << [ point, 0 ]
				end
			end
		end

		true
	end
end


class Rot90Hyp < RotHypothesis
	# h 4 2 correct center: [85.5, 24.5] - not detected!
	#		there are in fact two centers, diametrically opposite on the torus

	def initialize parent
		super parent, :ROT90
	end

	def do_test source, d, point

		return false unless test_target source, d, point, :rot90
		test_target source, d, point, :rot270
	end


	# Test quarter-rotational symmetry
	def test_sym sym, point
		$logger.info "entered"

		targets = get_targets point, sym, name

		# There are always two targets
		match = parent.match_range point, targets[0], :rot90
		return nil if match.nil?

		match2 = parent.match_range point, targets[1], :rot270
		return nil if match2.nil?

		detect_good_match( match, targets[0]) and  detect_good_match( match2, targets[1] )
	end
end


class Rot180Hyp < RotHypothesis

	def initialize parent
		super parent, :ROT180
	end


	def do_test source, d, point
		test_target source, d, point, :rot180
	end


	# Test half-rotational symmetry
	def test_sym sym, point
		$logger.info "entered"

		targets = get_targets point, sym, name
		# always one solution
		match = parent.match_range point, targets[0], :rot180
		return nil if match.nil?

		detect_good_match( match, targets[0])
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
		super + str
	end

	# Test slice symmetry
	def test_sym sym, point
		$logger.info "entered"

		targets = get_targets point, sym, name

		# Just do one step of the symmetry

		$logger.info "Entering match_square #{ point}, #{ targets[0] }, #{ orient }"
		match = parent.match_range point, targets[0], orient
		return nil if match.nil?

		detect_good_match match, targets[0]
	end
end


class Patterns

	Rot_tests = [ :ROT90, :ROT180 ]
	Line_tests = [ :DIAG_TLBR, :DIAG_BLTR, :HOR, :VERT]

	def add_square square
		$logger.info "Adding square #{ square } to patterns."
		@add_squares.push square
	end

	def initialize ai
		@add_squares = []
		@ai = ai
		@tests = []

		@radius = ( $ai.viewradius/Math.sqrt(2) ).to_i

		$logger.info "viewradius2: #{ $ai.viewradius2 }"
		$logger.info "radius: #{ @radius }"

		Hypothesis.set_ai ai
	end

	def init_fiber
		PatternsFiber.new self, @add_squares 
	end

	#
	# Count the number of true positive matches
	# test aborts if a true mismatch is encountered
	#
	def match_range sq1, sq2, how 
		matches = 0

		water_count = 0
		range = (-radius..radius)
		range.each do |row|
			Fiber.yield

			range.each do |col|
				sq_a = sq1.rel [ row, col ]
				sq_b = sq2.rel target_coord( row, col, how )

				next if sq_a.region.nil? or sq_b.region.nil?

				if sq_a.water? == sq_b.water?
					matches += 1
					water_count += 1 if sq_a.water?
				else
					return nil
				end

			end
		end

		# Mark matches without water as not valid
		matches = 0 if water_count == 0

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

		$logger.info "pattern region #{ square }:\n#{ str }" 
	end

	def radius 
		@radius	
	end


	#
	# Perform all possible fill-ins, based
	# on currently known symmetries.
	#
	def fill_map source
		did_blanks = false

		@tests.each do |test|
			next unless test.confirmed
			did_blanks = true

			fill_square test, source
		end

		did_blanks
	end


	def init_tasks
		rows = ai.rows
		cols = ai.cols

		# NOTE: rotational symmetry also occurs! See h 4 2
		# TODO: analyze this special case

		if rows == cols
			$logger.info "square board. Diagonal/rotational symmetry possible."

			@tests << Rot90Hyp.new( self )
			@tests << DiagHyp.new( self, :DIAG_BLTR, :ONE, :mir270,  nil, 1, 1 )
			@tests << DiagHyp.new( self, :DIAG_TLBR, :ONE, :mir90, nil, -1, 1 )
		end

		@tests << Rot180Hyp.new( self )
		@tests << HorVertHyp.new( self, :HOR, :ONE, :mir0, nil, 1, 0 )
		@tests << HorVertHyp.new( self, :VERT,:ONE, :mir180, nil, 0, 1 ) 

		# slices always possible
		row_dims = factors_of rows

		# At least 2 players
		# assume not more than 16 players
		row_dims.delete_if { |r| r[0] < 2 or r[0] >= 16 }
		$logger.info { "Row dimensions possible values: #{ row_dims }" }

		col_dims = factors_of cols
		col_dims.delete_if { |r| r[0] < 2 or r[0] >= 16 }
		$logger.info { "Col dimensions possible values: #{ col_dims }" }

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
		slice_tests = []
		dims.each  do |dim|
			# Coords in one direction may be multiples up to (not including) number of players
			(0...(dim[0])).each do | rfactor |
				(0...(dim[0])).each do | factor |
					next if rfactor == 0 and factor == 0

					test = SliceHyp.new( self, :SLICE, :ALL, :rot0, dim[0], rfactor*dim[1], factor*dim[2] )

					unless test_double test, slice_tests
						slice_tests << test 
					end
				end
			end
		end

		@tests += slice_tests


		$logger.info "done"
	end

	# Pre: all tests are slices
	def test_double t2, tests
		tests.clone.each do |t|
			#$logger.info { "Testing #{t2 } against #{t }" }

			if t.row_inc == t2.row_inc and t.col_inc == t2.col_inc
				$logger.info { "#{t2 } double; removing" }

				return true
			end

		end

		false
	end


	def match_tests source
		@tests.each do |test|
			unless test.confirmed
				test.test_match source
				test.confirm

				handle_confirm test if test.confirmed

				Fiber.yield
			end
		end

		# clean up negated tasks
		@tests.delete_if { |t| t.negated === true }
		@tests.compact!


		$logger.info { "Tests still in the running:\n\t#{ ( @tests.collect { |t| t.info} ).join( "\n\t") }" }
	end

	def all_confirmed
		result = true 
		@tests.each do |t|
			unless t.confirmed and t.complete
				result = false
				break
			end
		end

		result
	end

	private 

	def ai
		@ai
	end


	def fill_region source, target, orient
		#$logger.info "entered"

		return if target.done_region

		# Set all known water fields
		$region.all_region do |row, col|
			sq_a = source.rel [ row, col ]
			sq_b = target.rel target_coord( row, col, orient )

			# Sanity check; if water already present in target, 
			# it should also be in the source
			if sq_b.water? and not sq_a.water?
				raise "target has water, but source hasn't"
			end

			sq_b.water = sq_a.water
		end

		Fiber.yield

		# fill in the regions
		$region.find_regions target 
	end




	#
	#	Given the symmetry and the symmetry point, fill in the blanks
	#
	def fill_square test, source
		if source.done_region
			targets = test.get_source_targets source
			targets.each do |t|
				fill_region source, t[0], t[1]
			end
		end
	end


	#
	# Fill in the blanks for all known points
	# for a given test
	#
	def fill_all test 
		$logger.info "entered"

		(0...ai.rows).each do |row|
			Fiber.yield

			(0...ai.cols).each do |col|
				fill_square test, ai.map[row][col]
			end
		end
	end


	def handle_confirm test
		$logger.info(true) {  "#{ test } is confirmed" }

		# Kill of the competing tests with incompatible symmetry
		$logger.info "remove incompatible symmetry tests"

		if test.name == :SLICE
			@tests.each do |t| 
				if (Rot_tests + Line_tests ).include? t.name 
					t.negated = true
				end
			end 
		elsif Line_tests.include? test.name 
			@tests.each do |t| 
				if (Rot_tests + [ :SLICE ] ).include? t.name 
					t.negated = true
				end
			end 
		elsif Rot_tests.include? test.name 
			@tests.each do |t| 
				if ( Line_tests + [ :SLICE ] ).include? t.name 
					t.negated = true
				end
			end 
		end

		# Use the info gained to fill the map
		# This is the preliminary fill; afterwards, every new ant step will
		# fill in symmetrically
		$logger.info "Fill in rest of map"
		priority = -2
		fill_all test 
		priority = -1

		# Determine new hill locations
				
		$logger.info "putting new hills on the map"
		ai.hills.each_pair do |key, owner|
			coord = key.split "_"
			coord.collect! { |c| c.to_i }
			source = Square.coord_to_square coord

			# Put them all on the map, irrespective of already present or not
			# class Hills filters out the hills already present

			targets = test.get_source_targets source
			targets.each do |t|
				# not using rotation type info in t[1],
				# not needed for one point
				# 100 is the number of a non-existent player
				if ai.hills.add 100,  [ t[0].row, t[0].col ]
					# It's a new hill, start a path search to it from all our hills
					ai.hills.each_friend do |c|
						$logger.info "starting search to the hill"
						Region.add_searches  c,  [ t[0] ], true
					end
				end
			end
		end

		test.complete = true
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
			[ col, -row ]
		when :rot180
			[ -row, -col ]
		when :rot270
			[ -col, row ]
		when :mir0
			[ -row, col ]
		when :mir90
			[ col, row ]
		when :mir180
			[ row, -col ]
		when :mir270
			[ -col, -row ]
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
