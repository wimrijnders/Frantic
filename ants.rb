# Ants AI Challenge framework
# by Matma Rex (matma.rex@gmail.com)
# Released under CC-BY 3.0 license
require 'distance.rb'


class Logger
	def initialize ai
		@log = true
		@@ai = ai
	end

	def info str
		@@ai.stdout.puts "- #{ str }" if @log
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
	attr_accessor :row, :col

	def initialize sq
		@row = sq.row
		@col = sq.col
	end

	def == a
		@row == a.row and @col == a.col
	end

end

	

class Order
	attr_accessor :order

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

	def target? t
		@square === t
	end
end


class Collective
	def initialize
		@ants = []
		@safe_count = 0
	end

	def add a
		@ants << a
	end

	def size
		@ants.length
	end

	def leader? a
		@ants[0] == a
	end

	def remove a
		is_leader = leader? a

		@ants.delete a

		if is_leader
			$logger.info "Removing leader."
			@ants.each do |b|
				b.remove_target_from_order a
			end
		end

		reassemble
	end	

	def move
		@ants.each do |a|
			next if a.moved?

			a.stay unless a.orders?
		end
	end

	def reassemble
		leader = nil
	
		count = 1	
		@ants.each do |a|
			if leader.nil?
				leader = a 
				next 
			end

			a.set_order( leader, :ASSEMBLE, [ count/2 , count % 2 ] )
			count += 1
		end
	end

	def threatened
		ret = false
		@ants.each do |a|
			ret = true and break if a.attacked?
		end

		if ret 
			@safe_count = 0
		else
			@safe_count += 1
		end

		if @safe_count > 10
			disband
		end

		ret
	end

	def disband
		$logger.info "Disbanding"
		leader = nil
		@ants.each do |a|
			leader = a if leader.nil?

			a.collective = nil
			a.remove_target_from_order leader
		end

		@ants = []
	end
end


# Represents a single ant.
class Ant
	@@curleft = true

	# Owner of this ant. If it's 0, it's your ant.
	attr_accessor :owner
	# Square this ant sits on.
	attr_accessor :square, :moved_to
	
	attr_accessor :alive, :ai
	attr_accessor :collective

	
	def initialize alive, owner, square, ai
		@alive, @owner, @square, @ai = alive, owner, square, ai

		@want_dir = nil
		@next_dir = nil

		@left = @@curleft
		@@curleft = !@@curleft

		@moved= false

		@attack_distance = nil
		@orders = []
	end


	#
	# Perform some cleanup stuff when an ant dies
	#
	def die
		@collective.remove self	if collective?
	end
	
	def alive?; @alive; end
	def dead?; !@alive; end
	def mine?; owner==0; end
	def enemy?; owner!=0; end
	def row; @square.row; end
	def col; @square.col; end
	
	# Order this ant to go in given direction.
	# Equivalent to ai.order ant, direction.

	def order direction
		@square.neighbor( direction ).moved_here = self
		@moved= true
		@moved_to= direction

		@ai.order self, direction
	end

	def square= sq
		@square = sq
	end

	def stay
		$logger.info "Ant stays."
		@square.moved_here = self
		@moved = true
		@moved_to = nil
	end

	def evade_dir dir
		if @left
			left dir
		else 
			right dir
		end
	end

	def evade2_dir dir
		if @left
			right dir
		else 
			left dir
		end
	end

	def evade dir
		# The direction we want to go is blocked;
		# go round the obstacle
		$logger.info "Starting evasion" if @want_dir.nil?
	
		done = false
		newdir = dir

		# Don't try original direction again
		(0..2).each do
			newdir = evade_dir newdir
			if square.neighbor(newdir).passable?
				done = true
				break
			end
		end
	
		if done
			@want_dir = dir if @want_dir.nil?
			@next_dir = evade2_dir newdir
			order newdir
		else
			stay
		end
	end


	def evading
		unless @next_dir.nil?
			$logger.info "evading next_dir"

			if square.neighbor( @next_dir ).passable?
				order @next_dir

				# if the direction went corresponds with the
				# direction wanted, we are done.
				if @next_dir == @want_dir
					$logger.info "evasion complete"
					@next_dir = nil
					@want_dir = nil
				else
					@next_dir = evade2_dir @next_dir
				end
			else 
				evade @next_dir
			end

			return true
		end

		false
	end

	def moved= val
		@moved = val
	end

	def moved?
		@moved
	end


	def move dir
		if square.neighbor(dir).passable?
			order dir
		else
			if square.neighbor( dir ).water?
				evade dir
			else
				unless attacked?
					# Just pick any direction we can move to
					directions = [:N, :E, :S, :W ]
					directions.each do |dir|
						sq = square.neighbor( dir )
						if sq.passable?
							order dir
							return
						end
					end
				end

				# no directions left or under attack
				stay
			end
		end
	end

	#
	# Move ant to specified direction vector
	#
	def move_dir d
		move d.dir( @square)
	end

	#
	# Move ant in the direction of the specified square
	# 
	def move_to to
		move_dir Distance.new( @square, to)
	end

	def retreat
		return if attack_distance.nil?

		$logger.info "Retreat."
		move_dir attack_distance.invert
	end


	def evading?
		!@next_dir.nil?
	end

	def check_attacked
		d = closest_enemy self, self.ai.enemy_ants 
		unless d.nil?
			if d.in_view? and d.clear_view @square
				$logger.info "ant attacked!"

				@attack_distance = d
				return true
			end
		end

		@attack_distance = nil
		false
	end

	def attacked?
		!@attack_distance.nil?
	end

	def attack_distance
		@attack_distance
	end

	def set_order square, what, offset = nil
		n = Order.new(square, what, offset)

		@orders.each do |o|
			# order already present
			return if o.square == n.square
		end

		# ASSEMBLE overrides the rest of the orders
		if what == :ASSEMBLE
			@orders = []
		end

		@orders << n
	end

	def orders?
		@orders.size > 0
	end

	def remove_target_from_order t
		if orders?
			p = nil
			@orders.each do |o|
				p = o and $logger.info("Found p") and break if o.target? t
			end

			@orders.delete p unless p.nil?
		end
	end

	def handle_orders
		return false if moved?

		prev_order = (orders?) ? @orders[0].square: nil

		while orders?
			if self.square == @orders[0].square
				# Done with this order, reached the target
				$logger.info "Reached the target at #{ @orders[0].square.row }, #{ @orders[0].square.col }"
				@orders = @orders[1..-1]
				next
			end

			# Check if in-range when visible for food
			if @orders[0].order == :FORAGE
				sq = @orders[0].square
				closest = closest_ant [ sq.row, sq.col], @ai
				unless closest.nil?
					d = Distance.new closest, sq

					if d.in_view? and !@ai.map[ sq.row ][sq.col].food?
						# food is already gone. Skip order
						@orders = @orders[1..-1]
						next
					end
				end
			end

			break
		end
		return false if !orders?

		if evading?
			if prev_order != @orders[0].square
				# order changed; reset evasion
				@want_dir = nil
				@next_dir = nil
			else
				# Handle evasion elsewhere
				return false
			end
		end

		if @orders[0].order == :ASSEMBLE
			$logger.info "Moving to #{ @orders[0].square.row }, #{ @orders[0].square.col }"
		end
		move_to @orders[0].square

		true
	end

	#
	# Return actual position of ant, taking
	# movement into account.
	#
	# In effect, this is the position of the ant
	# in the next turn.
	#
	def pos
		if moved? and not moved_to.nil?
			square.neighbor( moved_to )
		else
			square
		end
	end

	def collective?
		not @collective.nil? # and @collective.size > 0
	end

	def collective_leader?
		collective? and @collective.leader? self
	end

	def add_collective a
		if @collective.nil?
			@collective = Collective.new
			@collective.add self
		end

		@collective.add a
		a.set_collective @collective
		count = @collective.size() -1
		a.set_order( self, :ASSEMBLE, [ count/2, count%2 ] )
	end

	def set_collective c 
		@collective = c
	end

	def make_collective 
		@collective =Collective.new 
		@collective.add self
	end

	def move_collective 
		@collective.move
	end
end




# Represent a single field of the map.
class Square
	# Ant which sits on this square, or nil. The ant may be dead.
	attr_accessor :ant
	# Which row this square belongs to.
	attr_accessor :row
	# Which column this square belongs to.
	attr_accessor :col
	
	attr_accessor :water, :food, :ai
	
	def initialize water, food, ant, row, col, ai
		@water, @food, @ant, @row, @col, @ai = water, food, ant, row, col, ai

		@moved_here = nil
		@visited = 0
	end
	
	# Returns true if this square is not water.
	def land?; !@water; end
	# Returns true if this square is water.
	def water?; @water; end
	# Returns true if this square contains food.
	def food?; @food; end

	# Square is passable if it's not water,
	# it doesn't contain alive ants and it doesn't contain food.
	#
	# In addition, no other friendly ant should have moved here.
	def passable?
		return false if water? or food?  or moved_here? 
		if ant?
			return false if @ant.enemy?

			# If there was an ant there,
			# but it is moving this turn,
			# then you can safely enter the square
			return false if @ant.pos == self
		end

		true
	end

	def moved_here?
		!@moved_here.nil?
	end

	def moved_here= val 
		@moved_here = val
	end

	def moved_here
		@moved_here
	end

	
	# Returns true if this square has an alive ant.
	def ant?; @ant and @ant.alive?; end;
	
	# Returns a square neighboring this one in given direction.
	def neighbor direction
		direction=direction.to_s.upcase.to_sym # canonical: :N, :E, :S, :W
	
		case direction
		when :N
			row, col = @ai.normalize @row-1, @col
		when :E
			row, col = @ai.normalize @row, @col+1
		when :S
			row, col = @ai.normalize @row+1, @col
		when :W
			row, col = @ai.normalize @row, @col-1
		else
			raise 'incorrect direction'
		end
		
		return @ai.map[row][col]
	end

	def visited= val
		@visited = val
	end
	def visited
		@visited
	end

	def == n
		self.row == n.row and self.col == n.col
	end
end


class AI
	# Map, as an array of arrays.
	attr_accessor :map
	# Number of current turn. If it's 0, we're in setup turn. If it's :game_over, you don't need to give any orders; instead, you can find out the number of players and their scores in this game.
	attr_accessor	:turn_number
	
	# Game settings. Integers.
	attr_accessor :loadtime, :turntime, :rows, :cols, :turns, :viewradius2, :attackradius2, :spawnradius2, :seed
	# Radii, unsquared. Floats.
	attr_accessor :viewradius, :attackradius, :spawnradius
	
	# Following vailable only after game's over.

	# Number of players.
	attr_accessor :players
	# Array of scores of players (you are player 0).
	attr_accessor :score
	attr_accessor :stdout

	# Initialize a new AI object.
	# Arguments are streams this AI will read from and write to.
	def initialize stdin=$stdin, stdout=$stdout
		@stdin, @stdout = stdin, stdout

		@map=nil
		@turn_number=0
		
		@my_ants=[]
		@enemy_ants=[]
		@food = []
		
		@did_setup=false
	end
	
	# Returns a read-only hash of all settings.
	def settings
		{
			:loadtime => @loadtime,
			:turntime => @turntime,
			:rows => @rows,
			:cols => @cols,
			:turns => @turns,
			:viewradius2 => @viewradius2,
			:attackradius2 => @attackradius2,
			:spawnradius2 => @spawnradius2,
			:viewradius => @viewradius,
			:attackradius => @attackradius,
			:spawnradius => @spawnradius,
			:seed => @seed
		}.freeze
	end
	
	# Zero-turn logic. 
	def setup # :yields: self
		read_intro
		yield self
		
		@stdout.puts 'go'
		@stdout.flush
		
		@map=Array.new(@rows){|row| Array.new(@cols){|col| Square.new false, false, nil, row, col, self } }
		@did_setup=true
	end
	
	# Turn logic. If setup wasn't yet called, it will call it (and yield the block in it once).
	def run &b # :yields: self
		setup &b if !@did_setup
		
		over=false
		until over
			over = read_turn
			yield self
			
			@stdout.puts 'go'
			@stdout.flush
		end
	end

	# Internal; reads zero-turn input (game settings).
	def read_intro
		rd=@stdin.gets.strip
		warn "unexpected: #{rd}" unless rd=='turn 0'

		until((rd=@stdin.gets.strip)=='ready')
			_, name, value = *rd.match(/\A([a-z0-9]+) (\d+)\Z/)
			
			case name
			when 'loadtime'; @loadtime=value.to_i
			when 'turntime'; @turntime=value.to_i
			when 'rows'; @rows=value.to_i
			when 'cols'; @cols=value.to_i
			when 'turns'; @turns=value.to_i
			when 'viewradius2'; @viewradius2=value.to_i
			when 'attackradius2'; @attackradius2=value.to_i
			when 'spawnradius2'; @spawnradius2=value.to_i
			when 'seed'; @seed=value.to_i
			else
				warn "unexpected: #{rd}"
			end
		end
		
		@viewradius=Math.sqrt @viewradius2
		@attackradius=Math.sqrt @attackradius2
		@spawnradius=Math.sqrt @spawnradius2
	end
	
	# Internal; reads turn input (map state).
	def read_turn
		ret=false
		rd=@stdin.gets.strip
		
		if rd=='end'
			@turn_number=:game_over
			
			rd=@stdin.gets.strip
			_, players = *rd.match(/\Aplayers (\d+)\Z/)
			@players = players.to_i
			
			rd=@stdin.gets.strip
			_, score = *rd.match(/\Ascore (\d+(?: \d+)+)\Z/)
			@score = score.split(' ').map{|s| s.to_i}
			
			ret=true
		else
			_, num = *rd.match(/\Aturn (\d+)\Z/)
			@turn_number=num.to_i
		end
	
		# reset the map data
		@map.each do |row|
			row.each do |square|
				square.food=false
			end
		end
		
		# @my_ants=[]
		@enemy_ants=[]

		@food = []
		
		until((rd=@stdin.gets.strip)=='go')
			_, type, row, col, owner = *rd.match(/(w|f|a|d) (\d+) (\d+)(?: (\d+)|)/)
			row, col = row.to_i, col.to_i
			owner = owner.to_i if owner
			
			case type
			when 'w'
				@map[row][col].water=true
			when 'f'
				@map[row][col].food=true

				@food << [ row, col ]
			when 'a'
				a=Ant.new true, owner, @map[row][col], self

				if owner==0
					unless @map[row][col].moved_here?
						$logger.info "New ant."

						@map[row][col].ant = a
						@map[row][col].visited += 1
						my_ants.push a
					else
						$logger.info "Moved ant."
						b = @map[row][col].moved_here 
						@map[row][col].ant = b
						@map[row][col].visited += 1
						b.square = @map[row][col] 
					end

				else
					enemy_ants.push a
				end
			when 'd'
				if owner==0
					if @map[row][col].moved_here?
						$logger.info "My ant died!."
						
						@map[row][col].moved_here.die
						my_ants.delete @map[row][col].moved_here
					else
						$logger.info "Dead ant unexpected!"
						if @map[row][col].ant
							$logger.info "But there WAS an ant here..."
							@map[row][col].ant.die
							@map[row][col].ant = nil
						end
					end
				end

				d=Ant.new false, owner, @map[row][col], self
				@map[row][col].ant = d
			when 'r'
				# pass
			else
				warn "unexpected: #{rd}"
			end
		end

		# reset the moved ants 
		@map.each do |row|
			row.each do |square|
				unless square.moved_here.nil?
					square.moved_here.moved = false
					square.moved_here.moved_to = nil
					square.moved_here = nil
					square.ant=nil
				end
			end
		end

		return ret
	end
	
	
	
	# call-seq:
	#   order(ant, direction)
	#   order(row, col, direction)
	#
	# Give orders to an ant, or to whatever happens to be in the given square (and it better be an ant).
	def order a, b, c=nil
		if !c # assume two-argument form: ant, direction
			ant, direction = a, b
			@stdout.puts "o #{ant.row} #{ant.col} #{direction.to_s.upcase}"
		else # assume three-argument form: row, col, direction
			col, row, direction = a, b, c
			@stdout.puts "o #{row} #{col} #{direction.to_s.upcase}"
		end
	end
	
	
	
	
	# Returns an array of your alive ants on the gamefield.
	def my_ants; @my_ants; end
	# Returns an array of alive enemy ants on the gamefield.
	def enemy_ants; @enemy_ants; end

	def food; @food; end
	
	# If row or col are greater than or equal map width/height, makes them fit the map.
	#
	# Handles negative values correctly (it may return a negative value, but always one that is a correct index).
	#
	# Returns [row, col].
	def normalize row, col
		[row % @rows, col % @cols]
	end

	def rows
		@rows
	end

	def cols
		@cols
	end
end
