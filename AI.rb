# Ants AI Challenge framework
# by Matma Rex (matma.rex@gmail.com)
# Released under CC-BY 3.0 license
require 'Config.rb'
require 'Logger.rb'
require 'Timer.rb'
require 'support.rb'
require 'Square.rb'
require 'Evasion.rb'
require 'Orders.rb'
require 'Distance.rb'
require 'Analyze.rb'
require 'MoveHistory.rb'
require 'Collective.rb'
require 'Harvesters.rb'
require 'Food.rb'
require 'Turn.rb'
require 'Fibers.rb'
require 'PointCache.rb'
require 'Region.rb'
require 'Patterns.rb'
require 'Ant.rb'
require 'Hills.rb'

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
	attr_reader :turn

	# Initialize a new AI object.
	# Arguments are streams this AI will read from and write to.
	def initialize stdin=$stdin, stdout=$stdout
		@stdin, @stdout = stdin, stdout

		@map=nil
		@turn_number=0
		
		@my_ants=[]
		@enemy_ants=[]
		@food = FoodList.new self
		
		@did_setup=false
		@hills = Hills.new 
		@do_throttle = false

	end
	
	# Returns a read-only hash of all settings.
	def settings
		{
			:loadtime      => @loadtime,
			:turntime      => @turntime,
			:rows          => @rows,
			:cols          => @cols,
			:turns         => @turns,
			:viewradius2   => @viewradius2,
			:attackradius2 => @attackradius2,
			:spawnradius2  => @spawnradius2,
			:viewradius    => @viewradius,
			:attackradius  => @attackradius,
			:spawnradius   => @spawnradius,
			:seed          => @seed
		}.freeze
	end
	
	# Zero-turn logic. 
	def setup 
		#$stderr.puts "Hello there!"

		read_intro
		@map=Array.new(@rows){|row| Array.new(@cols){|col| Square.new false, false, nil, row, col, self } }

		yield self if block_given?
		
		@turn = Turn.new  @turntime, @stdout
		
		@did_setup=true
	end


	def set_throttle
		val = $timer.get :yield

		#max_cap = @turntime*0.75
		max_cap = @turntime

		if @turn.maxed_out?
			$logger.info "maxed out: throttling."
			max_cap /= 2
		end

		if  val.nil? or val >= max_cap 
			$logger.info "Throttling set, val #{ val } hit max_cap #{ max_cap }"
			@do_throttle = true 
		else
			@do_throttle = false
		end

		# Limit number of ants 
		max_num_ants = AntConfig::THROTTLE_LIMIT

		if not @do_throttle and ( max_num_ants != -1 and my_ants.length >= max_num_ants )
			$logger.info { "Throttling set, num ants #{ my_ants.length } hit limit #{ max_num_ants }" }
			@do_throttle = true 
		end
	end

	def throttle?
		@do_throttle
	end	

	
	# Turn logic. If setup wasn't yet called, it will call it (and yield the block in it once).
	def run &b # :yields: self
		begin
			setup self  if !@did_setup
	
			over=false
			until over

				set_throttle

				$timer.start :total

				$timer.start( :read ) { over = read_turn }

				unless over 
					$timer.start :turn

					catch :maxed_out do
						$timer.start( :yield )    { 
							$timer.start( :turn_end ) { turn_end }

							yield self
						}

						@turn.check_time_limit

						$logger.debug(true) {

							# Bad idea, unfortunately; got a peak of > 600ms here
							# Only used for debugging porpoises
							$logger.info "garbage collecting"
							$timer.start( :garbage_collect ) {
								GC.start	
							}
						}

						@turn.check_time_limit

						$logger.info "fibers_resume"
						$timer.start( :fibers_resume ) {
							$fibers.resume
						}
					end

					$logger.info "sending go"
					@turn.go @turn_number


					$logger.info "=== Stay Phase ==="
					$timer.start( :stay ) {
						# Mark non-moved ants as staying; these are put at
						# the top of the list, so that they get processed
						# first next turn
						top = []
						bottom = [] 
						my_ants.each do |ant|
							if ant.moved?
								bottom << ant
							else
								ant.stay
								top << ant
							end
						end
						@my_ants = top + bottom
					}


					$timer.end :turn
				end

				$timer.end :total

				$logger.stats(true) { 
					str = ""

					# Don't display double when logging is on
					unless $logger.log? 
						str << "turn #{ @turn_number }\n"
					end

					str +
					"Num ants: #{ my_ants.length }; enemies: #{ @enemy_ants.length }\n" +
					$timer.display + "\n" + 
					$pointcache.status + "\n" +
					"Distance cache: " + Distance.status + "\n" +
					"GC count: #{ GC.count }\n" +
					AntObject.status + "\n" + 
					$fibers.status
				}
			end
			$logger.info "Exited game loop - goodbye"

			# It appears that you can time out on the end game turn
			# Following added to be sure
			@stdout.puts "go"
			@stdout.flush

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
		rd = nil
		$timer.start( :gets_strip ) {
			rd=@stdin.gets.strip
		}
	
		$timer.start :turn_init
	
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

		# Order important
		@turn.start @turn_number, $timer.get( :gets_strip )

		$logger.all { "turn #{ @turn_number }" }
	
		# reset the map data
		@map.each do |row|
			row.each do |square|
				square.food=false
				square.ant = nil
			end
		end


		@new_enemy_ants=[]
		@food.start_turn
		@hills.start_turn

		$timer.end :turn_init

		$timer.start :loop

		until((rd=@stdin.gets.strip)=='go')
			$timer.start :loop_intern

			_, type, row, col, owner = *rd.match(/(w|f|a|d|h) (\d+) (\d+)(?: (\d+)|)/)
			row, col = row.to_i, col.to_i
			owner = owner.to_i if owner
			
			sq = @map[row][col]

			case type
			when 'w'
				sq.water = true
			when 'f'
				sq.food=true

				@food.add [ row, col ]
			when 'h'
				if @hills.add owner, [row,col]
					if owner == 0 
						$logger.info { "My hill at #{ row },#{col}" }

						# Regions initialization
						if $region
							$region.assign_region sq
							$logger.info { "set region my hill to #{ sq.region }" }
						end
					else
						$logger.info { "Hill player #{ owner } at #{ row },#{col}" }
						# Active search in thread in anticipation
						Region.add_searches sq, my_ants
					end
				end
			when 'a'

				if owner==0
					a = MyAnt.new sq, self

					unless sq.moved_here?
						$logger.info { "New ant at #{ sq }." }
						my_ants.push a
					else
						a = sq.moved_here 
						$logger.info { "#{ a } to #{ sq }." }
						a.square =  sq
					end

					sq.ant = a
					sq.visited += 1
				else
					$logger.info { "New enemy ant at #{ sq }, owner #{ owner }." }
					enemy = EnemyAnt.new owner, sq, self
					add_enemy sq, enemy
				end
			when 'd'
				if owner==0
					if sq.moved_here?
						a = sq.moved_here 
						$logger.info { "My #{ a } died!" }
						
						sq.moved_here.die
						my_ants.delete sq.moved_here
					else
						$logger.info { "WARNING: Dead ant at #{ sq } unexpected!" }
					end
				else
					$logger.info { "Enemy ant died at #{ sq }, owner #{ owner }." }
					enemy = EnemyAnt.new owner, sq, self, false
					add_enemy sq, enemy
				end

			when 'r'
				# pass
			else
				warn "unexpected: #{rd}"
			end

			$timer.end :loop_intern
		end
		$timer.end :loop

		ret
	end


	def turn_end

		# reset the moved ants 
		@map.each do |row|
			row.each do |square|
				unless square.moved_here.nil?
					square.moved_here.reset_turn

					# For some reason, can't create a method within ant
					# which handles these resets. It screws up the movement
					square.moved_here.moved=false
					square.moved_here.moved_to=nil
					square.moved_here.prev_move = square.moved_here.moved_to
					square.moved_here.abspos=nil
					square.moved_here = nil
				end
			end
		end

		# determine all known squares and regions
		my_ants.each do |ant|
			Region.add_regions ant.square
		end unless $region.nil?

		$timer.start( :detect_enemies ) {
			detect_enemies @new_enemy_ants
		}

		$timer.start( :sort_friends_view ) {
			friends = sort_view my_ants
			add_sorted_view friends, false
		}
	end
	
	
	
	# call-seq:
	#   order(ant, direction)
	#   order(row, col, direction)
	#
	# Give orders to an ant, or to whatever happens to be
	# in the given square (and it better be an ant).
	#
	def order a, b, c=nil
		if !c # assume two-argument form: ant, direction
			ant, direction = a, b
			@turn.send "o #{ant.row} #{ant.col} #{direction.to_s.upcase}"
		else # assume three-argument form: row, col, direction
			col, row, direction = a, b, c
			@turn.send "o #{row} #{col} #{direction.to_s.upcase}"
		end
	end
	
	
	
	
	# Returns an array of your alive ants on the gamefield.
	def my_ants; @my_ants; end
	# Returns an array of alive enemy ants on the gamefield.
	def enemy_ants; @enemy_ants; end

	def food; @food; end
	
	#
	# If row or col are greater than or equal map width/height, makes them fit the map.
	#
	# Handles negative values correctly (it may return a negative value,
	# but always one that is a correct index).
	#
	# Returns [row, col].
	#
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
		@hills.remove [square.row, square.col]
	end

	def detect_enemies new_enemy_ants
		return if @enemy_ants.length == 0 and new_enemy_ants.length == 0

		$logger.info "Entered detect_enemies"

		# First, check new enemies wrt. previous ones
		$logger.info { "Pre new ants: #{ @enemy_ants.length} ants." }
		count = 0
		found_some = true
		while found_some  and @enemy_ants.length > 0
			count += 1
			found_some = false

			new_enemy_ants.each do |b|
				next if b.state?

				list = []
				@enemy_ants.each do |a|
					d = Distance.get b,a
					if d.dist == 1
						list << a
					end
				end

				if list.length == 1
					a = list[0]

					$logger.info "Found only one option for new ant"
					if b.dead?
						$logger.info { "Dead #{ b } detected" }
						# Use state for signalled this ant has been found
						b.state = true
					else
						$logger.info { "Alive #{ b } detected" }
						b.transfer_state a
					end

					@enemy_ants.delete a
					found_some = true
				end
			end
		end
		$logger.info { "post new ants: #{ @enemy_ants.length} ants; iterations: #{ count }" }
		
		# reset states for dead ants
		new_enemy_ants.each do |b|
			b.state = nil if b.dead? and b.state?
		end


		# Need to define list here for the lambda
		list = []
		lam = lambda do |a,dir|
			b = a.square.neighbor( dir ).ant
			list << b if b and b.enemy? and not b.state?
		end

		# Match the previous enemy ants with the new ones
		$logger.info { "Match pre: #{ @enemy_ants.length} ants." }
		count = 0
		found_some = true
		while found_some  and @enemy_ants.length > 0
			count += 1
			found_some = false

			# Handle ants with longest history list first
			antlist= @enemy_ants.sort do |a,b|
				# All current ants have state. No need to test
				b.state.length <=> a.state.length
			end

			$logger.info { "sorted antlist: #{ antlist }" }

			antlist.each do |a|
				list = []
				[ :STAY, :N, :E, :S, :W].each do |dir|
					lam.call a, dir
				end

				# Try by detected movement
				if list.length != 1
					if a.state.can_guess_dir?
						list = []
						$logger.info { "Can guess dir of #{ a }" }
						lam.call a, a.state.guess_dir
					end
				end


				if list.length == 1
					# Only add if there is one possibility
					b = list[0]
					if b.dead?
						$logger.info { "Dead #{ b } detected" }
					else
						$logger.info { "Alive #{ b } detected" }
						b.transfer_state a
					end

					# TODO: for some reason, ants do not get cleaned
					#       up on hills here. Find out why!
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
	
		# Clean up dead ants
		new_enemy_ants.clone.each do |a|
			if a.dead?
				a.square.ant = nil
				new_enemy_ants.delete a
				$logger.info { "Cleaned up dead #{ a.to_s }" }
			end
		end
	
		new_enemy_ants.each do |a|
			a.init_state unless a.state?
			$logger.info { a.to_s }
		end

		@enemy_ants = new_enemy_ants


if false
	if turn.maxed_urgent?
		# Screw the new enemies situation; retain the data from the previous
		# move and hope this helps a bit
	else
		$timer.start( :sort_enemies ) {
			@my_ants.each { |b| 
				# Don't sort enemies for collective followers
				next if b.collective_follower?

				b.add_enemies @enemy_ants
			}
		}
	end
end

		# NOTE: turn.maxed_urgent? not used here

		$timer.start( :sort_enemies_view ) {
			enemies2 = sort_view @enemy_ants
			add_sorted_view enemies2
		}

	end

	def add_sorted_view in_neighbors, do_enemies = true
		$logger.info "entered"

		my_ants.each do |a|
			neighbors = in_neighbors[a]
			next if neighbors.nil? or neighbors.length == 0

			PointCache.sort_valid neighbors

			if do_enemies
				list = a.enemies
			else
				list = a.friends
			end
			list = [] if list.nil?

			# Output has distance info only
			neighbors.each do |l|
				list << [ l[0], l[1][0] ]
			end
	
			#$logger.info {
			#	str = "After sort:\n"
			#	list.each do |result|
			#		str << "#{ result }\n"
			#	end
#
			#	str
			#}
		end
	end


	def sort_view from_list
		$logger.info "entered"

		neighbors = {}
		from_list.each do |e|
			ants = []
			$region.all_quadrant( e.square) do |sq|
				next unless sq.ant and sq.ant.mine?
				a = sq.ant

				# Don't sort enemies for collective followers
				next if a.collective_follower?

				item = $pointcache.get a.square, e.square
				next if item.nil?

				if neighbors[a].nil?
					neighbors[a] = [] 
				end
				neighbors[a] << [ e, item ]

				ants << a
			end

			# Let the backburner thread handle searching the path
			sq_ants   = Region.ants_to_squares ants
			Region.add_searches e.square, sq_ants
		end

		#$logger.info { "result: #{ neighbors } " }
		neighbors
	end


	def all_squares
		@map.each do |row|
			row.each do |square|
				yield square 
			end
		end
	end

	def add_enemy sq, enemy
		if sq.ant.nil?
			sq.ant = enemy 
			@new_enemy_ants.push sq.ant 
		else
			if @hills.hill? sq
				$logger.info { "Two ants defined on hill #{ sq }" }
				if enemy.dead? and sq.ant.alive?
					$logger.info "Current ant alive, keeping that one."
				elsif enemy.alive? and sq.ant.dead?
					$logger.info "Current ant dead, replacing."
					@new_enemy_ants.delete sq.ant
					sq.ant = enemy 
					@new_enemy_ants.push enemy 
				else
					$logger.info { "WARNING: Two live ants defined on hill #{ sq }. Keeping current." }
				end
			else
				$logger.info { "WARNING: Dead enemy ant at #{ sq } on same spot as other ant!" }
			end
		end
	end
end


#
# Global component initialization
#


#GC.disable

$ai=AI.new
$logger = Logger.new $ai
$timer = Timer.new
Coord.set_ai $ai

$ai.setup do |ai|
	$logger.info "Doing setup"

	Distance.set_ai ai
	ai.harvesters = Harvesters.new ai.rows, ai.cols, ai.viewradius2
	$region = Region.new ai
	Pathinfo.set_region $region
	$patterns = Patterns.new ai
	$pointcache = PointCache.new ai
	$fibers = Fibers.new.init_fibers
end

if false
# Tryouts with exit handlers

at_exit { 
	#puts "AAARGH! I'm dead!" 
	$logger.info "I'm dead!"
}

Signal.trap("HUP") { 
	$logger.info "Ouch!"
}

Signal.list.keys.each do |k|
	if [ "VTALRM", "CONT" ].include? k
		#Signal.trap( k, proc {
		#	$logger.q "I just trapped #{ k }"
		#} )
	else
		Signal.trap( k, proc {
			puts "I just trapped #{ k }"
			$logger.info "I just trapped #{ k }"
		} )
	end
end

end
