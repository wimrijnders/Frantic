
class Distance
	attr_accessor :row, :col

	# Lesson learnt: need to set explicitly for class var's
	@@ai = nil
	@@danger_radius2 = nil
	@@peril_radius2 = nil

	def self.set_ai ai
		@@ai = ai
	end

	def initialize from, to = nil
	if to.nil?
		if from.respond_to? :row
			@row = from.row
			@col = from.col
		else
			@row = from[0]
			@col = from[1]
		end
	else
		if to.respond_to? :row
			@row = to.row
			@col = to.col
		else
			@row = to[0]
			@col = to[1]
		end

		if from.respond_to? :row
			@row -= from.row
			@col -= from.col
		else
			@row -= from[0]
			@col -= from[1]
		end
	end

		normalize
	end


	def normalize
		ai = @@ai

		# If the distance is greater than half the width/height,
		# try the other side of the torus
		if @row.abs > ai.rows/2
			if @row > 0
				@row -= ai.rows
			else
				@row += ai.rows
			end
		end
	
		if @col.abs > ai.cols/2
			if @col > 0
				@col -= ai.cols
			else
				@col += ai.cols
			end
		end
	end

	def dist
		@row.abs + @col.abs
	end

	def invert
		Distance.new [0,0], [ -self.row, -self.col ]
	end

	def clone
		Distance.new [0,0], [ self.row, self.col ]
	end


	def in_view?
		( @row*@row + @col*@col ) <= @@ai.viewradius2
	end

	def in_attack_range?
		( @row*@row + @col*@col ) <= @@ai.attackradius2
	end

	#
	# Convert distance into compass direction
	#
	def dir square = nil
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
		#return ret_dir unless ret_dir.nil? or ( !square.nil? and !square.neighbor( ret_dir).passable? )
	

		# If specified, take passability from square into account
		unless square.nil?	
			# If one of the directions is blocked,
			# and the other isn't, choose the other one
			if !square.neighbor(rowdir).passable?
				if square.neighbor(coldir).passable?
					ret_dir = coldir
				end
			elsif !square.neighbor(coldir).passable?
				if square.neighbor(rowdir).passable?
					ret_dir = rowdir
				end
			end
		end
		
		if ret_dir.nil?
			# Otherwise, choose longest distance
			if rdif.abs > cdif.abs
				ret_dir = rowdir
			else
				ret_dir = coldir
			end
		end
	
		ret_dir
	end

	def clear_view square
		sq = square
		d = Distance.new self

		while d.dist > 0 and not d.in_attack_range?
			dir = d.dir

			if sq.neighbor( dir).water?
				return d.in_attack_range?
			end

			sq = sq.neighbor( dir)
			case dir
			when :N
				d.row += 1
			when :E
				d.col -= 1
			when :S
				d.row -= 1
			when :W
				d.col += 1
			end
		end

		d.in_attack_range?
		#true
	end


	#
	# Following is a good approach if the ant attacking has buddies.
	# A single ant has less chance.
	#
	def attack_dir 
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

	def longest_dir 
		if row.abs > col.abs
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


	def longest_dist
		if row.abs > col.abs
			row
		else
			col
		end
	end


	#
	# Check if we are close to being attacked.
	#
	# Following adds 1 square around viewradius2 == 5, 
	# it seems like a good heuristic. Other viewradiuses
	# are untested.
	#
	def in_danger?
		if @@danger_radius2.nil?
			# Lazy fetch, because values are prob not 
			# present when AI is added to this class
			@@danger_radius2 = (@@ai.attackradius + Math.sqrt(2) ) ** 2
			$logger.info "danger_radius2: #{ @@danger_radius2 }"
		end

		$logger.info "in_danger radius2: #{ ( @row*@row + @col*@col ) }"
		( @row*@row + @col*@col ) <= @@danger_radius2
	end

	#
	# Same as in_danger, but adds two squares around viewradius2 == 5
	#
	def in_peril?
		if @@peril_radius2.nil?
			# Lazy fetch, because values are prob not 
			# present when AI is added to this class
			@@peril_radius2 = (@@ai.attackradius + 2*Math.sqrt(2) ) ** 2
			$logger.info "peril_radius2: #{ @@peril_radius2 }"
		end

		$logger.info "in_peril radius2: #{ ( @row*@row + @col*@col ) }"
		( @row*@row + @col*@col ) <= @@peril_radius2
	end


	#
	# Adjust distance for direction followed
	#
	def adjust dir
		case dir
		when :N
			@row += 1
		when :E
			@col -= 1
		when :S
			@row -= 1
		when :W
			@col += 1
		end
	end

	def to_s
		"distance ( #{ row }, #{col} )"
	end
end

