
class Logger
	def initialize ai
		@log = AntConfig::LOG_OUTPUT
		@@ai = ai
		@start = Time.now

		@f = {}
		@q = []
	end

	def q str
		return unless @log

		@q << str
	end
	

	def info str = nil
		# setting str to boolean value 'true' and passing 
		# a block forces override of log inhibition.
		# I use this to output timer info without outputting 
		# regular traces
		return unless @log or str === true

		time = (Time.now - @start)*1000

		if Thread.current != Thread.main
			thread = Thread.current[ :name ]
		else 
			thread = "Main"
		end

		if @f[thread].nil?	
			if Thread.current != Thread.main
				filename = thread + "_log.txt"
			else 
				filename = "log.txt"
			end

			@f[ thread ] = File.new( filename, "w")
		end

		if block_given?
			 str = yield
		end

		out thread, "#{ time.to_i } - #{ caller_method_name}: #{ str }"
	end

	def log= val
		@log = val
	end

	private

	def out thread, str
		while qval = @q.pop
			@f[ thread ].write "queue: #{ qval }\n"
		end

		@f[ thread ].write str + "\n"
		@f[ thread ].flush

		#@@ai.stdout.puts str 
		#@@ai.stdout.flush
	end


	# Source: http://snippets.dzone.com/posts/show/2787
	def caller_method_name
    	parse_caller(caller(2).first).last
	end

	def parse_caller(at)
	    if /^(.+?):(\d+)(?::in `(.*)')?/ =~ at
	        file = Regexp.last_match[1]
			line = Regexp.last_match[2].to_i
			method = Regexp.last_match[3]

		    if /^block.* in (.*)/ =~ method
				method = Regexp.last_match[1]
			end

			[file, line, method]
		end
	end
end


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

	def display
		#$logger.info (true) {
		$logger.info {
			str = "Timer results:\n";
			max_k = nil
			@list.each_pair do |k,v|
				if max_k.nil? or max_k.length < k.length
					max_k = k
				end
			end

			lines = []
			@list.each_pair do |k,v|
				value = ( (v[1] - v[0])*1000 ).to_i 
				lines << [ 
					"   %-#{ max_k.length }s:%5d msec; max%5d msec" % [ k, value, @max[k] ],
					 v[2]
				]
			end

			lines.sort! { |l1, l2| l1[1] <=> l2[1] }

			str + lines.transpose[0].join( "\n" )
		}
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

	

class Order
	attr_accessor :order, :offset

	def initialize square, order, offset = nil
		@square = square
		@order = order
		@offset = offset
		@liaison = nil
	end

	#
	# NOTE: square actually returns a coord!
	#
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

	def to_s
		"Order #{ order }, #{ @square }, offset #{ @offset }"
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

	def clear_liaison
		@liaison = nil
	end

	def handle_liaison cur_sq, ai
		sq = ai.map[ square.row][ square.col ]
		return sq unless $region 

		if @liaison
			# First condition is to keep on moving to final target, 
			# when all liaisons are passed.
			if @liaison != sq and ( @liaison == cur_sq or $region.clear_path(cur_sq, @liaison ) )
				$logger.info { "Order #{ order } clear path to liaison #{ @liaison }" }
				@liaison = nil
			end
		end

		unless @liaison
			liaison  = $region.path_direction cur_sq, sq
			if liaison.nil?
				$logger.info { "WARNING: No liason for order #{ order } to target #{ sq }" }

				# We must have drifted off the path - restart search
				Region.add_searches sq, [ cur_sq ], true 

				# Don' specify move at this moment
				return nil

			elsif false === liaison
				$logger.info "no liaison needed - move directly"
				# Note that we use the liaison member for the target move
				@liaison = sq
			else
				@liaison = liaison
			end
		end

		$logger.info { "handle_liaison current #{ cur_sq } moving to #{ @liaison }" }
		ai.map[ @liaison.row][ @liaison.col ]
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
