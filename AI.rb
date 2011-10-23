# Ants AI Challenge framework
# by Matma Rex (matma.rex@gmail.com)
# Released under CC-BY 3.0 license
require 'Config.rb'
require 'support.rb'
require 'Square.rb'
require 'Evasion.rb'
require 'Orders.rb'
require 'Distance.rb'
require 'AttackDistance.rb'
require 'MoveHistory.rb'
require 'Collective.rb'
require 'Harvesters.rb'
require 'Region.rb'
require 'Ant.rb'


class AI
	def defensive?
		my_ants.length < AntConfig::DEFENSIVE_LIMIT
	end


	# Map, as an array of arrays.
	attr_accessor :map

	# Number of current turn.
	#
	# If it's 0, we're in setup turn.
	# If it's :game_over, you don't need to give any orders; instead,
	# you can find out the number of players and their scores in this game.
	attr_accessor	:turn_number
	
	# Game settings. Integers.
	attr_accessor :loadtime, :turntime, :rows, :cols, :turns,
		:viewradius2, :attackradius2, :spawnradius2, :seed

	# Radii, unsquared. Floats.
	attr_accessor :viewradius, :attackradius, :spawnradius
	
	# Following vailable only after game's over.

	# Number of players.
	attr_accessor :players
	# Array of scores of players (you are player 0).
	attr_accessor :score
	attr_accessor :stdout

	attr_accessor :hills, :harvesters

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
		@hills = {}
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
	def setup 
		read_intro
		yield self if block_given?
		
		@stdout.puts 'go'
		@stdout.flush
		
		@map=Array.new(@rows){|row| Array.new(@cols){|col| Square.new false, false, nil, row, col, self } }
		@did_setup=true
	end

	
	# Turn logic. If setup wasn't yet called, it will call it (and yield the block in it once).
	def run &b # :yields: self
		begin
			setup &b if !@did_setup
		
			over=false
			until over
				$logger.info { "Start read turn" }
				over = read_turn
				$logger.info { "End read turn, start yield" }
				yield self
				$logger.info { "End yield" }
			
				@stdout.puts 'go'
				@stdout.flush
			end
		rescue => e
			puts "Exception - SystemStackError?"
			print e.backtrace.join("\n")
			raise e
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
				square.ant=nil
			end
		end
	
		@my_ants.each do |a|
			a.enemies = []
		end
	
		# @my_ants=[]
		#@enemy_ants=[]
		new_enemy_ants=[]

		@food = []
	
		$logger.info { "start loop"}	
		until((rd=@stdin.gets.strip)=='go')
			_, type, row, col, owner = *rd.match(/(w|f|a|d|h) (\d+) (\d+)(?: (\d+)|)/)
			row, col = row.to_i, col.to_i
			owner = owner.to_i if owner
			
			sq = @map[row][col]

			case type
			when 'w'
				sq.water = true
			when 'f'
				sq.food=true

				@food << [ row, col ]
			when 'h'
				# TODO: there can be multiple hills per owner.
				#       Fix the hash
				# Also, be careful with the region setting!
				if owner == 0 and @hills[0].nil?
					$logger.info { "My hill at #{ row },#{col}" }
					@hills[ owner ] = [ row, col ]

					# Regions initialization
					sq.region = 0
				elsif @hills[ owner ].nil?
					$logger.info { "Hill player #{ owner } at #{ row },#{col}" }
					@hills[ owner ] = [ row, col ]
				end
			when 'a'

				if owner==0
					a = MyAnt.new sq, self

					unless sq.moved_here?
						$logger.info { "New ant at #{ sq }." }
						my_ants.push a
					else
						a = sq.moved_here 
						$logger.info { "Moved ant from #{ a.square } to #{ sq }." }
						a.square =  sq
					end

					sq.ant = a
					sq.visited += 1
				else
					$logger.info { "New enemy ant at #{ sq }, owner #{ owner }." }
					a= EnemyAnt.new owner, sq, self

					sq.ant = a
					new_enemy_ants.push a
				end
			when 'd'
				if owner==0
					if sq.moved_here?
						$logger.info { "My ant at #{ sq } died!" }
						
						sq.moved_here.die
						my_ants.delete sq.moved_here
					else
						$logger.info { "Dead ant at #{ sq } unexpected!" }
					end
				else
					$logger.info { "Enemy ant died at #{ sq }, owner #{ owner }." }
				end

				# No need to remember dead ants; they don't obstruct
				#d=Ant.new false, owner, sq, self
				#sq.ant = d
			when 'r'
				# pass
			else
				warn "unexpected: #{rd}"
			end
		end
		$logger.info { "end loop" }

		# reset the moved ants 
		@map.each do |row|
			row.each do |square|
				unless square.moved_here.nil?
					# For some reason, can't create a method within ant
					# which handles these resets. It screws up the movement
					square.moved_here.moved=false
					square.moved_here.moved_to=nil
					square.moved_here.friends=nil
					square.moved_here.abspos=nil
					square.moved_here = nil
				end
			end
		end

		# Match the previous enemy ants with the new ones
		$logger.info { "Match pre: #{ @enemy_ants.length} ants." }
		count = 0
		found_some = true
		while found_some  and @enemy_ants.length > 0
			count += 1
			found_some = false
			@enemy_ants.each do |a|
				list = []
				b = a.square.ant
				list << b if b and b.enemy? and b.alive? and not b.state?
				b = a.square.neighbor( :N ).ant
				list << b if b and b.enemy? and b.alive? and not b.state?
				b = a.square.neighbor( :E ).ant
				list << b if b and b.enemy? and b.alive? and not b.state?
				b = a.square.neighbor( :S ).ant
				list << b if b and b.enemy? and b.alive? and not b.state?
				b = a.square.neighbor( :W ).ant
				list << b if b and b.enemy? and b.alive? and not b.state?

				if list.length == 1
					list[0].transfer_state a
					@enemy_ants.delete a
					found_some = true
				end
			end
		end

		# Anything that's left, we match in their current position.
		found_some = true
		while found_some  and @enemy_ants.length > 0
			count += 1
			found_some = false
			@enemy_ants.each do |a|
				list = []
				b = a.square.ant
				list << b if b and b.enemy? and b.alive? and not b.state?

				if list.length == 1
					$logger.info { "Found the ant." }
					list[0].transfer_state a
					@enemy_ants.delete a
					found_some = true
				end
			end
		end


		$logger.info { "Match post: #{ @enemy_ants.length} ants; iterations: #{ count }" }
		
		new_enemy_ants.each do |a|
			a.init_state unless a.state?
			$logger.info { a.to_s }
		end

		@enemy_ants = new_enemy_ants

		$logger.info { "Sorting pre" }
		@my_ants.each do |b|
			@enemy_ants.each do |a|
				b.add_enemy a 
			end
			b.sort_enemies
		end
		$logger.info { "Sorting post" }

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

	
	def kamikaze?
		AntConfig::KAMIKAZE_LIMIT != -1 and my_ants.length >= AntConfig::KAMIKAZE_LIMIT
	end

	def aggresive?
		my_ants.length >= AntConfig::AGGRESIVE_LIMIT
	end

	def clear_raze square
		count = 0
		my_ants.each do |ant|
			ret = ant.remove_target_from_order square
			count += 1 if ret
		end

		$logger.info { "Cleared #{ count } raze targets."	}

		# also remove from hills list
		@hills.each_pair do |k,l|
			if l[0] == square.row and l[1] == square.col
				$logger.info { "Removing hill on #{ square.to_s } from list" }
				@hills.delete k
			end
		end
	end
end


#
# Global component initialization
#


$ai=AI.new
$logger = Logger.new $ai
Distance.set_ai $ai
Coord.set_ai $ai
