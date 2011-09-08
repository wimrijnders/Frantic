$:.unshift File.dirname($0)
require 'ants.rb'

# Local methods

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
	#return false if ant.moved?

	if ant.attacked? 
		if not ant.collective?
			ant.make_collective

			# recruit near neighbours for a collective
			ant.ai.my_ants.each do |l|
				next if l.collective?
				next if l === ant

				d = Distance.new ant.pos, l.pos	
				if d.in_view?
					ant.add_collective l
				end
			end

		end

		return
	else
		if !ant.collective?

			ant.ai.my_ants.each do |l|
				next unless l.collective_leader?
				next if l === ant

				d = Distance.new ant.pos, l.pos	

				if d.in_view?
					l.add_collective ant
				end
			end
		end
	end


end


def handle_conflict ant
	return false if ant.moved?

	if ant.attacked?
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

			ant.move_dir ant.attack_distance
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

ai.setup do |ai|
	# your setup code here, if any
end

ai.run do |ai|
	# your turn code here

	# Determine which ant are being attacked
	# if an enemy close by, move to your closest neighbour if present
	conflict = false
	ai.my_ants.each do |ant|
		conflict ||= ant.check_attacked
	end


	#if conflict
		ai.my_ants.each do |ant|
			handle_conflict2 ant
		end
	#end


	ai.my_ants.each do |ant|
		ant.handle_orders
	end

	# Move collectives as a whole
	ai.my_ants.each do |ant|
		next unless ant.collective_leader?

		next unless ant.collective.threatened

		if !ant.moved? 
			if ant.collective.size == 1 and ant.attacked?
				ant.retreat
			else
				ant.stay
			end
		end

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
		next if ant.collective? and not ant.orders?

		if !ant.evading
			default_move ant
		end
	end

	# Anything left here stays on the spot
	ai.my_ants.each do |ant|
		next if ant.moved?
		ant.stay
	end
end
