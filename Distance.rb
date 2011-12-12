
class Distance  < AntObject
	attr_accessor :row, :col

	# Derived values
	attr_reader :dist, :longest_dist, :shortest_dir

	@@cache = {}
	@@hit = 0
	@@miss = 0

	# Lesson learnt: need to set explicitly for class var's
	@@ai = nil
	@@danger_radius2 = nil
	@@peril_radius2 = nil

	def self.set_ai ai
		$logger.info { "entered" }

		@@ai = ai

		$logger.info "attackradius2: #{ ai.attackradius2 }"

		#
		# danger_radius contains the squares form which you can be attacked
		# in 1 move.
		# Radius for normal attackradius of 5 is 17, which is exact.
		#
		# Given calculation is a sort of safeguard for if the radius might change
		@@danger_radius2 = ( Math.sqrt(ai.attackradius2() -1 ) + 2  ) ** 2 + 1
		$logger.info "danger_radius2: #{ @@danger_radius2 }"

		#
		# same as peril radius, but contains squares from which you can be attacked in
		# moves. for attackradius 5 the value is 37. This is not exact, contains some
		# extra squares on the diagonal sides.
		# Again, safeguard calculation
		@@peril_radius2 = ( Math.sqrt(ai.attackradius2() -1 ) + 4  ) ** 2 + 1
		$logger.info "peril_radius2: #{ @@peril_radius2 }"


		# Find smallest square which fits into given viewradius
		radius = 1
		while 2*(radius + 1)*(radius + 1) <= ai.viewradius2
			radius +=1
		end
		$logger.info { "Found view-square with radius #{ radius }" }

		@@view_square_dist = 2*radius + 1
	end


	def initialize from, to = nil
		super

		@row, @col = Distance.relpos from, to

		recalc
		#$logger.info { "Distance init #{ @row }, #{ @col }" }
	end


	def self.view_square_dist; @@view_square_dist; end

	def in_view?;         @in_view;         end
	def in_attack_range?; @in_attack_range; end

	#
	# Check if we are close to being attacked.
	#
	# Following adds 1 square around viewradius2 == 5, 
	# it seems like a good heuristic. Other viewradiuses
	# are untested.
	#
	def in_danger?; @in_danger; end


	#
	# Same as in_danger, but adds two squares around viewradius2 == 5
	#
	def in_peril?; @in_peril; end


	def self.get from, to = nil
		row, col = Distance.relpos from, to
	

		# read from cache
		r = @@cache[ row ]
		unless r.nil?
			c = r[ col ]
			unless c.nil?
				@@hit += 1
				return c
			end
		end

		# Not present in cache; add new distance
		@@miss += 1
		if r.nil?
			r = @@cache[ row ] = {}
		end

		# Following returns value
		r[ col ] = Distance.new [row, col]
	end


	def self.status
		"Hit: #{ @@hit }; miss: #{ @@miss }"
	end


	def invert
		Distance.get [0,0], [ -self.row, -self.col ]
	end


	#
	# Make a selection of given directions based
	# an accesibility from given square
	#
	def select_accessible square, dir1, dir2, land_only
		ret_dir = nil

		sq1 = square.neighbor(dir1)
		sq2 = square.neighbor(dir2)

		# If it's not where you're going, don't
		# get into cul-de-sacs if you can help it
		unless dist == 1
			return dir2 if sq1.hole?
			return dir1 if sq2.hole?
		end

		unless land_only 
			# If one of the directions is blocked,
			# and the other isn't, choose the other one
			if !sq1.passable? and sq2.passable?
				ret_dir = dir2
			elsif !sq2.passable? and sq1.passable?
				ret_dir = dir1
			end
		else
			# Otherwise, only check for water
			if !sq1.land? and sq2.land?
				ret_dir = dir2
			elsif !sq2.land? and sq1.land?
				ret_dir = dir1
			end
		end

		ret_dir
	end

	#
	# Convert distance into compass direction
	#
	def dir square = nil, land_only = false
		return :STAY if @row == 0 and @col == 0

		ret_dir = nil
	
		rdif = @row
		cdif = @col
	
		if rdif > 0
			rowdir = :S
		else
			rowdir = :N
		end
	
		if cdif > 0
			coldir = :E
		else
			coldir = :W
		end
	
		# If one of the directions is zero, choose the other one
		if rdif == 0
			ret_dir = coldir
		elsif cdif == 0
			ret_dir = rowdir
		end

		return ret_dir unless ret_dir.nil?

		# TODO: Note that following block does not take into 
		#       account if both ways are blocked!!!!	

		# If specified, take passability from square into account
		unless square.nil?	
			ret_dir = select_accessible square, rowdir, coldir, land_only
		end
		
		if ret_dir.nil?
			# Otherwise, choose longest distance
			if rdif.abs > cdif.abs
				ret_dir = rowdir
			else
				ret_dir = coldir
			end
		end
	
		#$logger.info "Final going to #{ ret_dir }"
		ret_dir
	end


	def self.direct_path? from, to
		walk = Distance.get_walk from, to
		return false if walk.length == 0
		walked_full_path = ( walk[-1][0] == to )

		if walked_full_path 
			$logger.info { "Direct path between #{ from } and #{ to }" }
		else
			$logger.info { "No direct path between #{ from } and #{ to }" }
		end

		walked_full_path
	end


	#
	# Make a shortest path between the two points.
	# If water is encountered, return path up till the water
	#
	# first item is from 
	# If full path has been made, last item is to
	#
	def self.get_walk from, to
		raise "from and to are equal: #{ from }-#{to}" if from == to

		d = Distance.get from, to
		sq = from

		result = []
		while d.dist > 0
			dir = d.dir

			next_sq = sq.neighbor( dir)

			result << [ sq, dir, d.dist ]

			break if next_sq.water?
			sq = next_sq 
			d = d.adjust dir
		end

		if d.dist == 0
			result << [ sq, :STAY, 0 ]
		end

		$logger.info { "made path: #{ result }" }

		result
	end


	def longest_dir 
		if row.abs == col.abs
			# randomize selection here, to avoid twitches
			# for collectives
			select = [true,false][ rand(2) ]
		else
			select = row.abs > col.abs
		end

		if select
			if row > 0
				return :S
			else
				return :N
			end
		else
			if col > 0
				return :E
			else
				return :W
			end
		end
	end

	#
	# Adjust distance for direction followed
	#
	def adjust dir
		row, col = @row, @col

		case dir
		when :N
			row += 1
		when :E
			col -= 1
		when :S
			row -= 1
		when :W
			col += 1
		end

		Distance.get [row, col]
	end

	

	#
	# Following is a good approach if the ant attacking has buddies.
	# A single ant has less chance.
	#
	def attack_dir
		# As long as we are too far away to receive damage, lessen the distance
		return longest_dir if not in_peril? 

		@attack_dir
	end


	def to_s
		"distance( #{ row }, #{col} )"
	end

	private

	#
	# Calculate all derived variables.
	# 
	# This needs to be done every time row, col values change
	def recalc

		# Precalculate as much as possible

		@dist = @row.abs + @col.abs

		@attack_dir = calc_attack_dir 

		radius = @row*@row + @col*@col
		#$logger.info "radius: #{ radius }"
		@in_view         = ( radius <= @@ai.viewradius2 )
		@in_attack_range = ( radius <= @@ai.attackradius2 )
		@in_peril        = ( radius <= @@peril_radius2 )
		@in_danger       = ( radius <= @@danger_radius2 )


		dist = nil
		if @row.abs > @col.abs
			dist = row
		else
			dist = col
		end
		@longest_dist = dist
	
		@shortest_dir = calc_shortest_dir
	end


	def calc_shortest_dir
		if row.abs < col.abs
			return nil if row == 0

			if row > 0
				dir = :S
			else
				dir = :N
			end
		else
			return nil if col == 0

			if col > 0
				dir = :E
			else
				dir = :W
			end
		end

		dir
	end


	def self.relpos from, to
		if to.nil?
			if from.respond_to? :row
				row = from.row
				col = from.col
			else
				row = from[0]
				col = from[1]
			end
		else
			if to.respond_to? :row
				row = to.row
				col = to.col
			else
				row = to[0]
				col = to[1]
			end
	
			if from.respond_to? :row
				row -= from.row
				col -= from.col
			else
				row -= from[0]
				col -= from[1]
			end
		end

		Distance.normalize row, col
	end


	def self.normalize row, col
		ai = @@ai

		# If the distance is greater than half the width/height,
		# try the other side of the torus
		rows = ai.rows
		if row.abs > rows/2
			if row > 0
				row -= rows
			else
				row += rows
			end
		end

		cols = ai.cols	
		if col.abs > cols/2
			if col > 0
				col -= cols
			else
				col += cols
			end
		end

		[ row, col ]
	end

	def calc_attack_dir 

		# Move sideways to optimize the attack force.
		# eg. more ants will hit the enemy at the same time
		if row.abs < 1
			if col > 0
				return :E
			else
				return :W
			end
		end
		if col.abs < 1
			if row > 0
				return :S
			else
				return :N
			end
		end

		if row.abs < col.abs
			if row > 0
				return :S
			else
				return :N
			end
		else
			if col > 0
				return :E
			else
				return :W
			end
		end
	end
end

