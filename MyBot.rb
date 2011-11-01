$:.unshift File.dirname($0)
#######################################
# TODO
#
# - IMPORTANT: Defend your hill; some players (include me!) are good at targetting
#   these.
#		- Especially, throw up a defence if enemy close.
# - 2-collectives can twitch when leader on diagonal to enemy ( eg. orient N/S and distance(-n,n) ).
# - Make defensive collectives less scared; if they can surely winning, attack or at the least hold ground
# - Improve attack resolution; handle multiple attackers.
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

	def enough_collectives ai
		num_collectives = 0
		ai.my_ants.each do |ant|
			num_collectives += 1 if ant.collective_leader?
		end
		num_ants = ai.my_ants.length

		if 2*num_collectives >=  num_ants/2
			$logger.info { "Enough collectives: #{ num_collectives } collectives for #{ num_ants }" }
			true
		else
			false
		end
	end

	#
	# Handle non-collective ants which are in a conflict situation
	#
	def ant_conflict ai
		$logger.info "=== Conflict Phase ==="

		$logger.info "check if own hills are safe"
		ai.hills.each_friend do |square| 
			# Find nearest enemies	
			near_enemies = BaseStrategy.nearby_ants_region square, ai.enemy_ants, true 
		
			attackers = []
			near_enemies.each do |enemy|
				d = Distance.new square, enemy 

				next if d.nil? or not d.in_view?

				attackers << enemy
			end

			if attackers.length > 0
				$logger.info { "#{ attackers } attacking my hill #{ square}!" }

				# Order all nearby ants to defend
				defenders = []
				near_friends = BaseStrategy.nearby_ants_region square, ai.my_ants, true 
				near_friends.each do |ant|
					defenders << ant
					unless ant.has_order  :DEFEND_HILL
						ant.set_order square, :DEFEND_HILL
					end
				end

				# Assign at least one blocker per attacker
				att_i = 0
				defenders.each do |d|
					unless d.has_order :ATTACK
						d.set_order attackers[ att_i ], :ATTACK
						att_i = ( att_i + 1 ) % attackers.length()
					end
				end
			else
				near_friends = BaseStrategy.nearby_ants_region square, ai.my_ants, true 
				if near_friends.length > 0
					$logger.info "Disbanding defenders"
					near_friends.each do |ant|
						ant.remove_target_from_order square
					end
				end
			end
		end


		$logger.info "Do individual conflict ants"
		ai.my_ants.each do |ant|
			next if ant.collective?
			ant.handle_conflict
		end
	end


	def turn ai
		check_attacked ai	

		$logger.info "=== Collective Phase ==="
		Collective.complete_collectives ai
		if not ai.kamikaze? 
			unless enough_collectives ai
				Collective.create_collectives ai unless ai.kamikaze? 
			else
			end
		end
		find_food ai
		ant_conflict ai

		$logger.info "=== Hill Phase ==="

		# preliminary test - let all available ants attack an anthill
		ai.hills.each_enemy do |owner, l|
			sq = ai.map[ l[0] ][ l[1] ]
			$logger.info { "Targetting hill #{ sq }" }

			# Make list of ants which are available for attacking the hill
			available_ants = []
			ai.my_ants.each do |ant|
				next unless ant.can_raze?

				# Insert some randomness, so that not all ants hit the
				# first hill in the list
				next if rand(2) == 0

				available_ants << ant
			end

			nearby_ants = BaseStrategy.nearby_ants_region sq, available_ants, true

			nearby_ants.each do |ant|
				ant.set_order sq, :RAZE
			end unless nearby_ants.nil?

		end if $region #and not ai.defensive?

		if ai.kamikaze? and ai.enemy_ants.length > 0
			$logger.info "=== Kamikaze Phase ==="
			ai.my_ants.each do |ant|
				next if ant.orders?
				next if ant.moved?

				# if not doing anything else, move towards a random enemy
				if ant.enemies and ant.enemies.length > 0
					enemy = ant.enemies[ Random.rand( ant.enemies.length ) ][0]
					ant.set_order enemy.square, :ATTACK
				end
			end
		end

		$logger.info "=== Harvester Enlist Phase ==="
		ai.my_ants.each do |ant|
			next if ant.moved?
			next if ant.collective?

			#next if Trail.follow_trail ant

			# If nothing else to do, turn into a harvester
			next if ant.orders?
			ai.harvesters.enlist ant
		end

		$logger.info "=== Move Collective Phase ==="
		Collective.move_collectives ai

		ant_orders ai

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
