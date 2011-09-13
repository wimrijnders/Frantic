# Ants AI Challenge framework
# by Matma Rex (matma.rex@gmail.com)
# Released under CC-BY 3.0 license

require 'support.rb'
require 'Square.rb'
require 'Evasion.rb'
require 'Distance.rb'
require 'Collective.rb'
require 'Ant.rb'



class AI
	def defensive?
		my_ants.length < Config::DEFENSIVE_LIMIT
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
		# Wierdest thin ever: just by adding the rescue block
		# the error SystemStackError - stack too deep disappeared
		#
		# Actually, it didn't; the bug is erratic :-(
		begin
			setup &b if !@did_setup
		
			over=false
			until over
				over = read_turn
				yield self
			
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
		
		# @my_ants=[]
		@enemy_ants=[]

		@food = []
		
		until((rd=@stdin.gets.strip)=='go')
			_, type, row, col, owner = *rd.match(/(w|f|a|d) (\d+) (\d+)(?: (\d+)|)/)
			row, col = row.to_i, col.to_i
			owner = owner.to_i if owner
			
			sq = @map[row][col]

			case type
			when 'w'
				sq.water = true
			when 'f'
				sq.food=true

				@food << [ row, col ]
			when 'a'
				a=Ant.new true, owner, sq, self

				if owner==0
					unless sq.moved_here?
						$logger.info "New ant."

						sq.ant = a
						sq.visited += 1
						my_ants.push a
					else
						b = sq.moved_here 
						$logger.info "Moved ant from #{ b.square } to #{ sq }."
						sq.ant = b
						sq.visited += 1
						b.square =  sq
					end

				else
					enemy_ants.push a
				end
			when 'd'
				if owner==0
					if sq.moved_here?
						$logger.info "My ant died!."
						
						sq.moved_here.die
						my_ants.delete sq.moved_here
					else
						$logger.info "Dead ant at #{ sq } unexpected!"
					end
				end

				d=Ant.new false, owner, sq, self
				sq.ant = d
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
					# For some reason, can't create a method within ant
					# which handles these resets. It screws up the movement
					square.moved_here.moved=false
					square.moved_here.moved_to=nil
					square.moved_here.friends=nil
					square.moved_here.enemies=nil
					square.moved_here = nil
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
