$:.unshift File.dirname($0)
#######################################
# TODO
#
# - IMPORTANT: Defend your hill; some players (include me!) are good at targetting
#   these.
#		- Especially, throw up a defence if enemy close.
# - 2-collectives can twitch when leader on diagonal to enemy ( eg. orient N/S and distance(-n,n) ).
# - Make defensive collectives less scared; if they can surely winning, attack or at the least hold ground
# - NB: improve detection of enemy moves - especially snakes like with GoSouth
#
# - Perhaps: use pattern symmetry to detect food.
# - Better raze attack. Currently, the horde is unorganized and tends to attack all hills at once.
# - Improve evasion (pathfinding?)
# - Pathfinder evasion for collectives
#
#======================================
#
# regions: don't assume hills centered; same parts are always mirrored/rotated
# food placed in same manner in all regions (obeys symmetry)
# slices: row/col distances are always board.[row|col]/num_players	- no rotations, mirrors
#
# maze -
#
#
#  even p - squares (sometimes with diagonal splits) or slices
#
#		- slices can also occur in 2p situation -> m 2 1
#       - see m 2 2 for diagonal split 
#
#	uneven p - always slices, as in random walk
#
# multi-hill -
#
#	m21	- mirrored halves; per half three hills, players inverse of other half
#	m22	- mirrored halves; 4 hills per half, player on own half
#	m31 - 3 slices; 8 hills per slice; players permuted per slice
#	m41 - slices; 6 hills per slice; players permuted (but obviously not all permutations 
#	m51 - slices; 5 hills per slice; players permuted
#	m61 - doesn't exist
#	m71	- slices; 4 hills per slice; permuted
#	m81	- quadrants divided diagonally; per 'triangle' 3 hills, different colours
#
#
# random walk -
#
#    always slices with equal distance between players
#
#######################################

ENABLE_PROFILING = false
NUM_TURNS 		 = 250

require 'AI.rb'
require 'BaseStrategy'


if ENABLE_PROFILING
	require 'ruby-prof'

	 # Profile the code
	RubyProf.start
end


class Strategy < BaseStrategy

	def default_move ant
		ant.move ant.default 
	end

	def enough_collectives ai
		num_collectives = 0
		ai.my_ants.each do |ant|
			num_collectives += 1 if ant.collective_leader?
		end
		num_ants = ai.my_ants.length

		if 2*num_collectives >=  num_ants*0.8
			$logger.info { "Enough collectives: #{ num_collectives } collectives for #{ num_ants }" }
			true
		else
			false
		end
	end


	#
	#
	#
	def defend_hills ai
		$logger.info "check if own hills are safe"

		ai.hills.each_friend do |square| 
			ai.turn.check_maxed_out

			# Find nearest enemies	
			near_enemies = BaseStrategy.nearby_ants_region square, ai.enemy_ants, true 
		
			attackers = []
			near_enemies.each do |enemy|
				d = Distance.get square, enemy 

				next if d.nil? or not d.in_view?

				attackers << enemy
			end

			if attackers.length > 0
				$logger.info { "#{ attackers } attacking my hill #{ square}!" }

				# Order all nearby ants to defend
				defenders = []
				near_friends = BaseStrategy.nearby_ants_region square, ai.my_ants, true 
				near_friends.each do |ant|
					next if Distance.get( ant, square).dist > 15

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
					first = true
					near_friends.each do |ant|
						if first
							$logger.info "Disbanding defenders"
							first = false
						end
						
						ant.clear_order :DEFEND_HILL
					end
				end
			end
		end
	end


	def handle_hills ai

		# preliminary test - let all available ants attack an anthill
		ai.hills.each_enemy do |owner, l|
			sq = ai.map[ l[0] ][ l[1] ]
			$logger.info { "Targetting hill #{ sq }" }

			# Determine if there are enemy ants defending 
			if ai.defensive?
				defenders = BaseStrategy.nearby_ants_region sq, ai.enemy_ants
				unless defenders.empty?
					$logger.info { 
						"Defensive mode and #{ defenders.length } defenders " +
						" for hill #{ sq}. Not razing."
					}

					next
				end
			end


			# Make list of ants which are available for attacking the hill
			# Note that collectives are added as well, we don't differentiate
			available_ants = []
			ai.my_ants.each do |ant|
				next if ant.has_order :RAZE, sq

				d = Distance.get sq, ant.square

				# If ant is in view of hill, it must attack
				# Even if it is razing elsewhere
				unless d.in_view?
					next unless ant.can_raze?
				
					# For the rest, insert some randomness,
					# so that not all ants hit the
					# first hill in the list
					next if rand(2) == 0
				end

				available_ants << ant
			end

			# Following needed for starting the path search to the hills!
			nearby_ants = BaseStrategy.nearby_ants_region sq, available_ants, true, -1, true

			nearby_ants.each do |ant|
				ant.set_order sq, :RAZE
			end unless nearby_ants.nil?


			# Do only one hill per turn
			break
		end
	end


	#
	# Main turn routine
	#
	def turn ai
		ai.turn.check_maxed_out

		if ai.throttle?
			$logger.info "=== Throttle Phase ==="

			# All ants on top of hills should stay put
			ai.hills.each_friend do |sq|
				if sq.ant? and sq.ant.mine?
					ant = sq.ant

					$logger.info { "#{ ant } staying put on hill due to throttle." }
					ant.stay
				end
			end
		end

		ai.turn.check_maxed_out
		$timer.start( :check_attacked ) {
			check_attacked ai	
		}


		ai.turn.check_maxed_out
		$logger.info "=== Analyze Phase ==="
		$timer.start( :analyze ) {
			Analyze.analyze ai
		}


		ai.turn.check_maxed_out
		#if ai.turn.maxed_urgent?
			# Try to complete all outstanding orders and hope for the best
			# with any luck, some of the next phases may be completed in tim.

			$logger.info "=== First Order Phase ==="
			$timer.start( :First_Order_Phase ) {
				ant_orders ai
			}

			ai.turn.check_maxed_out
			$logger.info "=== First Move Collective Phase ==="
			$timer.start( :First_Colmove_Phase ) {
				Collective.move_collectives ai
			}
		#end


	unless ai.turn.maxed_out?
		$logger.info "=== Pattern Phase ==="
		# Determine ant furthest away from first own active hill,
		# for the pattern matcher
		ai.hills.each_friend do |sq|
			furthest = BaseStrategy.nearby_ants_region( sq, ai.my_ants).reverse[0]

			if furthest
				$logger.info "furthest #{ furthest }."
				$patterns.add_square furthest.square

				# Note that last filled in value is remembered
				ai.furthest = furthest
			end
			break			# TODO: determine why this is here
		end
	end


		ai.turn.check_maxed_out
		unless ai.turn.maxed_out?
			$logger.info "=== Collective Phase ==="
			$timer.start :Collective_Phase

			Collective.complete_collectives ai

			if not ai.kamikaze? and not enough_collectives ai
				Collective.create_collectives ai unless ai.kamikaze? 
			end

			$timer.end :Collective_Phase
		end


		ai.turn.check_maxed_out
		$logger.info "=== Food Phase ==="
		$timer.start( :Food_Phase ) {
			find_food ai
		}


		ai.turn.check_maxed_out
		$logger.info "=== Conflict Phase ==="
		$timer.start( :Conflict_Phase ) {
			unless ai.turn.maxed_out?
				defend_hills ai
			end

			# Handle non-collective ants which are in a conflict situation
			ai.my_ants.each do |ant|
				next if ant.collective?
				next if ant.moved?

				ant.handle_conflict
			end
		}


		ai.turn.check_maxed_out
		unless ai.turn.maxed_out?
			$logger.info "=== Hill Phase ==="
			$timer.start( :Hill_Phase ) {
				handle_hills ai
			}
		end


		ai.turn.check_maxed_out
		if ai.kamikaze? and ai.enemy_ants.length > 0 # and not ai.turn.maxed_out?
			$logger.info "=== Kamikaze Phase ==="
			$timer.start :Kamikaze_Phase

			ai.my_ants.each do |ant|
				next if ant.orders?
				#next if ant.moved?

				# if not doing anything else, move towards  the nearest enemy
				enemy = ant.closest_enemy
				unless enemy.nil?
					ant.set_order enemy.square, :ATTACK
				end
			end

			$timer.end :Kamikaze_Phase
		end

if false
	# Disabled because static ants seriously impede ant traffic

		ai.turn.check_maxed_out
		$logger.info "=== Enlist Phase ==="
		$timer.start :Enlist_Phase
		# Don't harvest if	not enough ants
		if ai.my_ants.length > AntConfig::HARVEST_LIMIT and not ai.turn.maxed_out?
			ai.my_ants.each do |ant|
				next if ant.orders?
				next if ant.moved?
				next if ant.collective?
				#next if Trail.follow_trail ant

				# NB: disabled due to performance
				#     This may be false economy, though, because
				#     these calls, which cache the results, are also 
				#     called elsewhere
				#
				## Don't harvest if other ants around
				#next if ant.neighbor_friends( 10).length > 0
				next if ant.neighbor_enemies? 10

				# Don't harvest too close to own hills
				too_close = false
				ai.hills.each_friend do |sq|
					d = Distance.get sq, ant.square
					if d.in_view?
						too_close = true
						break
					end
				end
				next if too_close

				# If nothing else to do, turn into a harvester
				ai.harvesters.enlist ant
			end
		end
		$timer.end :Enlist_Phase
end


		ai.turn.check_maxed_out
		$logger.info "=== Second Move Collective Phase ==="
		$timer.start( :Second_Colmove_Phase ) {
			Collective.move_collectives ai
		}

		ai.turn.check_maxed_out
		$logger.info "=== Second Order Phase ==="
		$timer.start( :Second_Order_Phase ) {
			ant_orders ai
		}

		ai.turn.check_maxed_out
		$logger.info "=== Super Phase ==="
		$timer.start( :Super_Phase ) {
			super ai, false, false #, ( !ai.kamikaze? ) 
		}
	end
end


#
# main routine
#

strategy = Strategy.new

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
			printer.print( File.new("logs/profile2.txt","w"))
		
			$logger.info { "Profiling done." }
		end
	end

	# signal that we didn't max out
end
