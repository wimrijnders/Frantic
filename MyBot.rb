$:.unshift File.dirname($0)
#######################################
# TODO
#
# - Attacking collective: if only blocked by non-water, stay instead of evade.
# - Staying put is a good strategy for small playing fields.
# - 1-x ant combat; best approach is diagonal on corner ant. You die but you also kill one enemy.
# - On evasion, select shortest route (fast-forward?)
# - Break off evasion if under attack for collectives
# - Creating collectives: don't do it in the direct neighbourhood of water (fixed obstacles) 
#
# - URGENT! collective attack: 
#		- defensive: detect inert enemies, these render you immobile.
#		- Especially important for defensive behaviour. You can get stuck.
#
# - If attacked with no way of escape, defend as well as possible
#		- if ant is sure to die, let him take an enemy down
# - Retreat: for multiple attackers, select good escape route
#
#
#######################################

ENABLE_PROFILING = false
NUM_TURNS 		 = 265

require 'AI.rb'
require 'BaseStrategy'


if ENABLE_PROFILING
	require 'ruby-prof'

	 # Profile the code
	RubyProf.start
end


class Strategy < BaseStrategy

	def default_move ant
		return if ant.moved?
	
		ant.move ant.default 
	end


	#
	# Handle non-collective ants which are in a conflict situation
	#
	def ant_conflict ai
		ai.my_ants.each do |ant|
			next if ant.collective?
			ant.handle_conflict
		end
	end


	def turn ai
		check_attacked ai	

		ai.my_ants.each do |ant|
			$region.find_regions ant.square
		end

# Collectives disabled
#		Collective.complete_collectives ai
#		Collective.create_collectives ai unless ai.kamikaze? 
		ant_conflict ai
		ant_orders ai
		find_food ai

if false
		# preliminary test - let all ants attack an anthill
		ai.hills.each_enemy do |owner, l|

			ai.my_ants.each do |ant|
				next if not ant.orders?

				# Insert some randomness, so that not all ants hit the
				# first hill in the list
				next if rand(2) == 0

				ant.set_order ai.map[ l[0] ][ l[1] ], :RAZE
			end
		end

		if ai.kamikaze? and ai.enemy_ants.length > 0
			ai.my_ants.each do |ant|
				next if ant.orders?
				next if ant.moved?

				# if not doing anything else, move towards a random enemy
				enemy = ai.enemy_ants[ rand (ai.enemy_ants.length ) ]

				ant.set_order enemy.square, :ATTACK
			end
		end
end

		ai.my_ants.each do |ant|
			next if ant.moved?

			#next if Trail.follow_trail ant

			# If nothing else to do, turn into a harvester
			next if ant.orders?
			ai.harvesters.enlist ant
		end

		#Collective.move_collectives ai

		super ai, false, false #, ( !ai.kamikaze? ) 
	end
end


#
# main routine
#

strategy = Strategy.new

$ai.setup do |ai|
	ai.harvesters = Harvesters.new ai.rows, ai.cols, ai.viewradius2
	$region = Region.new ai
	Pathinfo.set_region $region
end

first = false

$ai.run do |ai|
	unless first
		$logger.info { "template:\n" + $region.to_s }
		$logger.info { ai.harvesters.to_s }
		first = true
	end

	# your turn code here
	$logger.info { "Start turn." }

	strategy.turn ai
	
	$logger.info { "End turn." }

	if ENABLE_PROFILING
		# Need to put this within the loop, otherwise 
		# no output is generated. I think this is something
		# to do with how IO is handled by the calling program
		#
		# Turn number should ideally be next to last. This
		# can't be determined while the program is running.
		#
		# -2 because zero-based and we want next-to-last turn.
		#
		if ai.turn_number == NUM_TURNS - 2
			result = RubyProf.stop
		
			#printer = RubyProf::FlatPrinter.new(result)
			printer = RubyProf::GraphPrinter.new(result)
			#printer.print(STDOUT)
			printer.print( File.new("profile4.txt","w"))
		
			$logger.info { "Profiling done." }
		end
	end
end


