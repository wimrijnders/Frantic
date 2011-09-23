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
#		- break flip-flop deadlock 
#		- detect ants which ignore you and keep on going in the same direction
#		- defensive: detect inert enemies, these render you immobile.
#
# - If attacked with no way of escape, defend as well as possible
#		- if ant is sure to die, let him take an enemy down
# - Retreat: for multiple attackers, select good escape route
#
# - BUG: Following appearing in the logs:
#
#   - 87756: collective3 ( 55, 82 ) relpos count: 3, orient: n # unknown action
#
#   Ie. one member too many TODO: Fix
#
# DOING
#
# - URGENT: Timeout problem because of sorting enemy ants.
#            TODO: NEEDS TO BE FIXED
#
# - Assembling collective: if new ants are made closer by than assembling ants,
#     use these new ants instead
#     	- ideal case: in exact necessary position
#
#######################################

ENABLE_PROFILING = false
NUM_TURNS 		 = 265

require 'Config.rb'
require 'support.rb'
require 'Square.rb'
require 'Evasion.rb'
require 'Distance.rb'
require 'Collective.rb'
require 'Ant.rb'
require 'AI.rb'


if ENABLE_PROFILING
	require 'ruby-prof'

	 # Profile the code
	RubyProf.start
end

# Local methods


def default_move ant
	return if ant.moved?

	directions = [:N, :E, :S, :W, :N, :E, :S, :W ]

	# go to the least visited square
	best_visited = nil
	best_dir = nil
	
	# Select preferred direction as longest direction on map.
	# This fills the map up faster with following approach
	index = 0
	if ant.ai.rows < ant.ai.cols
		index = 1
	end

	( directions[ index, 4] ).each do |dir|
		sq = ant.square.neighbor( dir )
	
		next unless sq.passable?
	
		val = sq.visited
		if !best_visited || val < best_visited
			best_visited = val
			best_dir = dir
		end
	end
	
	best_dir = directions[ index ] if best_dir.nil?
	
	ant.move best_dir 
end



def recruit ant

	# recruit near neighbours for a collective
	if ant.ai.defensive?
		friend_distance = 10
	else
		friend_distance = 20
	end

	recruits = ant.neighbor_friends friend_distance 
	recruits.delete_if { |a| a.collective? }

	# If there are enough, make the collective
	if recruits.size > 0 
		recruits.each do |l|
			ant.add_collective l, recruits.length
			break if ant.collective_assembled?
		end
		$logger.info "Created collective #{ ant.collective.to_s}"
	else
		# If not enough close by, disband the collective
		# These may then be used for other incomplete collectives
		catch :done do
			ant.collective.disband if ant.collective?
		end
	end
end


def handle_conflict ant
	return if ant.moved?

	# If we can complete the order before being in conflict, 
	# the order will take precedence.
	return if ant.check_orders

	if ant.attacked?
		ant.retreat and return if ant.ai.defensive?

		$logger.info "Conflict!"
		# Check for direct friendly neighbours 
		done = false
		has_neighbour = false
		[ :N, :E, :S, :W ].each do |dir|
			n = ant.square.neighbor( dir ).ant
			next if n.nil?

			has_neighbour = true

			if n.mine?
				if n.moved? and not n.moved_to.nil?
					# if neighbour moved, attempt the same move
					$logger.info "neighbour moved."
					ant.move n.moved_to
					done = true
					break
				end
			end
		end
		return if done


		if has_neighbour
			# Neighbours didn´t move, perform attack yourself
			$logger.info "Attack."

			#ant.move_dir ant.attack_distance
			ant.move ant.attack_distance.attack_dir
			return 
		end

		# Find a close neighbour and move to him
		d = closest_enemy ant, ant.ai.my_ants
		unless d.nil?
			dist = d.dist
			if dist == 1 
				$logger.info "next to friend."
				# already next to other ant
				ant.stay
			elsif dist < 20
				$logger.info "Moving to friend."
				ant.move_dir d
			end
			return 
		end

		# Otherwise, just run away
		ant.retreat
		return 
	else
		order_dist = ant.order_distance

		# Find an attacked neighbour and move in to help
		ant.ai.my_ants.each do |l|
			next unless l.attacked?

			d = Distance.new ant, l.pos	

			# Only help out if current ant has no order,
			# or ant in distress is nearer
			if order_dist and order_dist.dist < d.dist
				# Skip helping friend, we have other things to do
				next
			end

			if d.dist == 1 
				$logger.info "Moving in - next to friend."
				ant.stay
				return 
			elsif d.in_view?
				$logger.info "Moving in to help attacked buddy."
				ant.move_to l.pos
				return
			end
		end
	end
end

#
# main routine
#

ai=AI.new
$logger = Logger.new ai
Distance.set_ai ai
Coord.set_ai ai

ai.setup do |ai|
	# your setup code here, if any
end

ai.run do |ai|
	# your turn code here
	$logger.info "Start turn."

	# Determine which ants are being attacked
	ai.my_ants.each do |ant|
		# WOW WHAT A STUPID BUG!
		#conflict ||= ant.check_attacked
		ant.check_attacked
	end


	# Complete existing collectives first
	ai.my_ants.each do |ant|
		next unless ant.collective?
		next if ant.collective.assembled? false

		recruit ant
	end


	# Assemble new collectives
	ai.my_ants.each do |ant|
		next if ant.collective?

		next unless ant.attacked? 

		# Don't even think about assembling if not enough ants around
		next if ant.ai.my_ants.length < AntConfig::ASSEMBLE_LIMIT

		if ant.ai.defensive? 
			# If collective nearby, don't bother creating a new one
			collective_near = false
			ant.neighbor_friends( 10 ).each do |a|
				if a.collective?
					$logger.info "#{ ant.square.to_s } has collective nearby"
					collective_near = true
					break
				end
			end

			next if collective_near
		end

		# If too close too an assembling collective, 
		# don't bother creating a new one
		collective_near = false
		ant.neighbor_friends( 3 ).each do |a|
			if a.collective?
				$logger.info "#{ ant.square.to_s } assembling collective too close "
				collective_near = true
				break
			end
		end
		next if collective_near

		recruit ant
	end

	ai.my_ants.each do |ant|
		next if ant.collective?
		handle_conflict ant
	end


	ai.my_ants.each do |ant|
		#next if ant.collective_leader?
		ant.handle_orders
	end

	# Move collectives as a whole
	ai.my_ants.each do |ant|
		next unless ant.collective_leader?

		ant.move_collective
	end


	ai.food.each do |l|

		ant = closest_ant l, ai
		unless ant.nil?
			#next if ant.moved?
			next if ant.collective?

			ant.set_order ai.map[ l[0] ][ l[1] ], :FORAGE
		end
	end 


	ai.my_ants.each do |ant|
		next if ant.moved?
		ant.evading
	end

	ai.my_ants.each do |ant|
		next if ant.moved?
		next if ant.collective?

		default_move ant
	end

	# Anything left here stays on the spot
	ai.my_ants.each do |ant|
		next if ant.moved?
		ant.stay
	end

	
	$logger.info "End turn."

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

		$logger.info "Done."
	end
end

end


