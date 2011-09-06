
class Distance
	attr_accessor :row, :col

	@@ai

	def self.set_ai ai
		@@ai = ai
	end

	def initialize from, to
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
		@row *= -1
		@col *= -1

		self
	end

	def in_view?
		( @row*@row + @col*@col ) <= @@ai.viewradius2
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
			# Otherwise, choose shortest distance
			if rdif.abs > cdif.abs
				ret_dir = rowdir
			else
				ret_dir = coldir
			end
		end
	
		ret_dir
	end
end

