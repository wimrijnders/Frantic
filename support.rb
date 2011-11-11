
class Timer

	def initialize
		clear
		@max = {}
	end

	def start str
		@list[ str ] = [ Time.now, nil, @count ]
		@count += 1

		if block_given?
			yield
			self.end str
		end
	end

	def add_max str, value
		if @max[ str ].nil? or value > @max[str]
			@max[ str ] = value
		end
	end

	def end str
		v = @list[str]
		if v 
			v[1] = Time.now

			value = ( (v[1] - v[0])*1000 ).to_i 

			add_max str, value
		else
			$logger.info { "No start time for #{ str } " }
		end
	end

	def clear
		@list = {}
		@count = 0
	end


	def current str
		v = @list[str]
		value = nil
		if v 
			if v[1]
				value = ( ( v[1] - v[0])*1000 ).to_i 
			else
				value = ( ( Time.now - v[0])*1000 ).to_i 
			end
		end

		"Timer #{str}: #{value} msec"
	end


	def display
		str = "Timer results (msec):\n";
		max_k = nil
		@list.each_pair do |k,v|
			if max_k.nil? or max_k.length < k.length
				max_k = k
			end
		end

		lines = []
		uncomplete = []
		@list.each_pair do |k,v|
			if v[1].nil?
				uncomplete << k
				next
			end

			value = ( (v[1] - v[0])*1000 ).to_i 
			lines << [ 
				"   %-#{ max_k.length }s %5d %5d" % [ k, value, @max[k] ],
				 v[2]
			]
		end

		lines.sort! { |l1, l2| l1[1] <=> l2[1] }

		str <<
			"   %-#{ max_k.length }s %5s %5s\n" % [ "Label", "Value", "Max" ] <<
			"   %-#{ max_k.length }s %5s %5s\n" % [ "=" * max_k.length , "=" * 5, "=" * 5 ] <<
			lines.transpose[0].join( "\n" ) 

		if uncomplete.length > 0
			str << "\nDid not complete: " + uncomplete.join( ", ")
		end

		str
	end


	def get str
		v = @list[str]
		unless v.nil?
			( (v[1] - v[0])*1000).to_i
		else
			nil
		end
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

	



#
# Determine closest ant by way of view distance.
#
# This is the old style of distance determination and still
# useful when you are only interested in viewing
#
def closest_ant_view l, ai 
	ants = ai.my_ants 

	cur_best = nil
	cur_dist = nil

	ants.each do |ant|
		d = Distance.new ant, l
		dist = d.dist

		if !cur_dist || dist < cur_dist
			cur_dist = dist
			cur_best = ant
		end
	end

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
