
class Logger
	def initialize ai
		@log = AntConfig::LOG_OUTPUT
		@@ai = ai
		@start = Time.now
	end

	def info str = nil
		if @log
			time = (Time.now - @start)*1000
			if str
				@@ai.stdout.puts "- #{ time.to_i }: #{ str }"
			end
			if block_given?
				@@ai.stdout.puts "- #{ time.to_i } BLOCK: #{ yield }"
			end
			@@ai.stdout.flush
		end
	end

	def log= val
		@log = val
	end
end



def right dir
	newdir = case dir
		when :N; :E 
		when :E; :S 
		when :S; :W 
		when :W; :N 
	end

	newdir
end

def left dir
	newdir = case dir
		when :N; :W 
		when :W; :S 
		when :S; :E 
		when :E; :N 
	end

	newdir
end

def reverse dir
	newdir = case dir
		when :N; :S 
		when :W; :E 
		when :S; :N 
		when :E; :W 
	end

	newdir
end


class Coord
	@@ai = nil;

	attr_accessor :row, :col

	def self.set_ai ai
		@@ai = ai
	end

	def normalize
		@row, @col = @@ai.normalize @row, @col
	end

	def initialize sq, col = nil
		if col
			@row = sq
			@col = col
		else
			@row = sq.row
			@col = sq.col
		end

		normalize
	end

	def == a
		@row == a.row and @col == a.col
	end

	def to_s
		"( #{ row }, #{col} )"
	end

	def row= v
		@row = v
		normalize
	end	

	def col= v
		@col = v
		normalize
	end	
end

	

class Order
	attr_accessor :order, :offset

	def initialize square, order, offset = nil
		@square = square
		@order = order
		@offset = offset
	end

	def square
		if @square.respond_to? :square
			sq = Coord.new @square.square
		else
			sq = Coord.new @square
		end

		if !@offset.nil?
			sq.row += @offset[0]
			sq.col += @offset[1]
		end

		sq
	end


	def square= v
		@square = v
	end

	def sq_int
		@square
	end

	def target? t
		@square == t
	end

	def == a
		sq_int.class ==a.sq_int.class and 	# target square can have differing classes
		sq_int.row == a.sq_int.row and		
		sq_int.col == a.sq_int.col and
		order == a.order and
		( ( offset.nil? and a.offset.nil? ) or
		  (	offset[0] == a.offset[0] and offset[1] == a.offset[1] )
		)
	end

	def add_offset offs
		if @offset.nil?
			@offset = offs
		else
			@offset[0] += offs[0]
			@offset[1] += offs[1]
		end
	end
end



def closest_ant l, ai 
	
	$logger.info { "closest_ant start" }

	ants = ai.my_ants 

	cur_best = nil
	cur_dist = nil

	ants.each do |ant|

		unless $region
			# Use the old distance approach for bots which 
			# don't have regions implemented
			d = Distance.new ant, l
			dist = d.dist
		else
			pathinfo = Pathinfo.new ant.square, ai.map[ l[0] ][ l[1] ]
			next unless pathinfo.path?
			dist = pathinfo.dist	
		end

		if !cur_dist || dist < cur_dist
			cur_dist = dist
			cur_best = ant
		end
	end

	$logger.info { "closest_ant end" }
	cur_best
end

#
# Following derived from Harvesters
#

	def check_spot ai, r,c, roffs, coffs
		coord = Coord.new( r + roffs, c + coffs)

		if ai.map[ coord.row ][ coord.col ].land?
			# Found a spot
			# return relative position
			throw:done, [ roffs, coffs ]
		end
	end

def nearest_non_water sq
	return sq if sq.land?

	r = sq.row
	c = sq.col
	rows = sq.ai.rows 
	cols = sq.ai.cols 

		offset = nil
		radius = 1

		offset = catch :done do	

			diameter = 2*radius + 1
			while diameter <= rows or diameter <= cols 
	
				# Start from 12 o'clock and move clockwise

				0.upto(radius) do |n|
					check_spot sq.ai, r, c, -radius, n
				end if diameter <= cols

				(-radius+1).upto(radius).each do |n|
					check_spot sq.ai, r, c, n, radius
				end if diameter <= rows

				( radius -1).downto( -radius ) do |n|
					check_spot sq.ai, r, c, radius, n
				end if diameter <= cols

				( radius - 1).downto( -radius ) do |n|
					check_spot sq.ai, r, c, n, -radius
				end if diameter <= rows

				( -radius + 1).upto( -1 ) do |n|
					check_spot sq.ai, r, c, -radius, n
				end if diameter <= cols

				# End loop
				radius += 1
				diameter = 2*radius + 1
			end
		end

		offset
end
