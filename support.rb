
class Logger
	def initialize ai
		@log = AntConfig::LOG_OUTPUT
		@@ai = ai
		@start = Time.now
	end

	def info str
		time = (Time.now - @start)*1000
		if @log
			@@ai.stdout.puts "- #{ time.to_i }: #{ str }"
			@@ai.stdout.flush
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
end


#
# Deprecated: ants have @enemies list, sorted by distance
#
# TODO: check if also OK for friendly ants.
#
def closest_enemy ant, enemies

	cur_best = nil
	cur_dist = nil

	enemies.each do |l|
		next if l.nil?

		# Stuff for friendly ants
		if l.mine?
			# skip self
			next if l === ant
			to = l.pos
			next if l.evading?		# Needed because you can trap an evading ant by following it
		else
			to = l.square
		end

		d = Distance.new ant, to

		# safeguard
		next if d.dist == 0

		if !cur_dist || d.dist < cur_dist
			cur_dist = d.dist
			cur_best = d
		end
	end

	cur_best
end


def closest_ant l, ai 

	ants = ai.my_ants 

	cur_best = nil
	cur_dist = nil

	ants.each do |ant|

		d = Distance.new ant, l

		if !cur_dist || d.dist < cur_dist
			cur_dist = d.dist
			cur_best = ant
		end
	end

	cur_best
end

