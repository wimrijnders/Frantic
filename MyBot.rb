$:.unshift File.dirname($0)
require 'ants.rb'

# Local methods

def closest_enemy ant, enemies 

	cur_best = nil
	cur_dist = nil

	enemies.each do |l|
		next if l.nil?

		# Stuff for friendly ants

		# skip self
		next if l === ant
		if l.moved?
			sq = l.square.neighbor( l.moved_to )
			to = sq.row
		else
			to = l.row
		end
		next if l.evading?		# Needed because you can trap an evading ant by following it

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


	# go to the least visited square
	best_visited = nil
	best_dir = nil
	[:N, :E, :S, :W ].each do |dir|
		sq = ant.square.neighbor( dir )

		next unless sq.passable?

		val = sq.visited
		if !best_visited || val < best_visited
			best_visited = val
			best_dir = dir
		end
	end

	best_dir = :E if best_dir.nil?
	#best_dir = [ :N, :E, :S, :W ][ rand(4) ] if best_dir.nil?

	ant.move best_dir 
end






def handle_conflict ant
	return false if ant.moved?

	if ant.attacked?
		$logger.info "Conflict!"
if false
		# Check for direct friendly neighbours 
		done = false
		has_neighbour = false
		[ :N, :E, :S, :W ].each do |dir|
			n = ant.square.neighbor( dir ).ant
			next if n.nil?

			has_neighbour = true

			if n.mine? and n.moved? 
				# if neighbour moved, attempt the same move
				$logger.info "neighbour moved."
				ant.move n.moved_to
				done = true
				break
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
		# TODO: following should take moved ant into account
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
end

		# Otherwise, just run away
		$logger.info "Retreat."
		ant.move_dir ant.attack_distance.invert
		return true
	end

	false
end

#
# main routine
#

ai=AI.new
Distance.set_ai ai

ai.setup do |ai|
	# your setup code here, if any
end

ai.run do |ai|
	# your turn code here

	# Determine which ant are being attacked
	# if an enemy close by, move to your closest neighbour if present
	ai.my_ants.each do |ant|
		ant.check_attacked
	end


	ai.my_ants.each do |ant|
		ant.evading
		#handle_conflict ant
		ant.handle_orders
	end




	ai.food.each do |l|
		ant = closest_ant l, ai
		unless ant.nil?
			next if ant.moved?

			ant.set_order ai.map[ l[0] ][ l[1] ], :FORAGE
		end
	end 


	ai.my_ants.each do |ant|
		next if ant.moved?

		default_move ant
	end
end
