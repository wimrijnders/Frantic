$:.unshift File.dirname($0)
#######################################
# TODO
#
# - Attacking collective: if only blocked by non-water, stay instead of evade.
# - Staying put is a good strategy for small playing fields.
# - 1-x ant combat; best approach is diagonal on corner ant. You die but you also kill one enemy.
# - On evasion, select shortest route (fast-forward?)
# - Sad but true: collectives are a bad strategy for small, cramped (lots of water and enemies) maps.
# - Second previous comment; 4-collectives absolutely suck
# - :-) Even on big maps with >4 players (symmetric_4), non-collectives are better (crying now)
# - Strategy: need balance between foraging and fighting. Sometimes
#             this bot is too aggresive.
# - Break off evasion if under attack for collectives
# - Creating collectives: don't do it in the direct neighbourhood of other
#   assembling collectives.
# - collective attack: break flip-flop deadlock
#
#######################################
require 'AI.rb'


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



def handle_conflict2 ant


		if ant.collective?
			return unless ant.collective.leader? ant
			return if ant.collective.filled?
			threshold = ant.collective.fullsize - ant.collective.size
		else 
			return unless ant.attacked? 

			# Don't even think about assembling if not enough ants around
			return if ant.ai.my_ants.length < Config::ASSEMBLE_LIMIT

			if ant.ai.defensive? 
				return if ant.order_closer_than_attacker?

				# If collective nearby, don't bother creating a new one
				collective_near = false
				ant.neighbor_friends( 20 ).each do |a|
					if a.collective?
						$logger.info "#{ ant.square.to_s } has collective nearby"
						collective_near = true
						break
					end
				end

				return if collective_near
			end

			# If too close too an assembling collective, don't bother
			# If collective nearby, don't bother creating a new one
			collective_near = false
			ant.neighbor_friends( 3 ).each do |a|
				if a.collective?
					$logger.info "#{ ant.square.to_s } assembling collective too close "
					collective_near = true
					break
				end
			end
			return if collective_near


			threshold = 1
		end

		# recruit near neighbours for a collective
		if ant.ai.defensive?
			friend_distance = 10
		else
			friend_distance = 20
		end

		recruits = ant.neighbor_friends friend_distance 
		recruits.delete_if { |a| a.collective? }

		# If there are enough, make the collective
		if recruits.size >= threshold 
			recruits.each do |l|
				ant.add_collective l, recruits.length
				break if ant.collective.filled?
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
	return false if ant.moved?

	if ant.attacked?
		ant.retreat and return true if ant.ai.defensive?
		return false if ant.order_closer_than_attacker?

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
		return true if done


		if has_neighbour
			# Neighbours didn´t move, perform attack yourself
			$logger.info "Attack."

			#ant.move_dir ant.attack_distance
			ant.move ant.attack_distance.attack_dir
			return true
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
			return true
		end

		# Otherwise, just run away
		ant.retreat
		return true
	else
		# Find an attacked neighbour and move in to help
		ant.ai.my_ants.each do |l|
			next unless l.attacked?

			d = Distance.new ant, l.pos	
			if d.dist == 1 
				$logger.info "Moving in - next to friend."
				ant.stay
				return true
			elsif d.in_view?
				$logger.info "Moving in to help attacked buddy."
				ant.move_to l.pos
				return true
			end
		end
	end

	false
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

	# Determine which ant are being attacked
	# if an enemy close by, move to your closest neighbour if present
	ai.my_ants.each do |ant|
		# WOW WHAT A STUPID BUG!
		#conflict ||= ant.check_attacked
		ant.check_attacked
	end


	# Collectives first
	ai.my_ants.each do |ant|
		next unless ant.collective?
		handle_conflict2 ant
	end
	ai.my_ants.each do |ant|
		next if ant.collective?
		handle_conflict2 ant
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
end
