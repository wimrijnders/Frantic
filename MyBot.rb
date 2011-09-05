$:.unshift File.dirname($0)
require 'ants.rb'

# Local methods

def norm_distance ai, distance, ll = nil
	# If the distance is greater than half the width/height,
	# try the other side of the torus
	if distance[0].abs > ai.rows/2
		if distance[0] > 0
			distance[0] -= ai.rows
			ll[0] -= ai.rows unless ll.nil?
		else
			distance[0] += ai.rows
			ll[0] += ai.rows unless ll.nil?
		end
	end

	if distance[1].abs > ai.cols/2
		if distance[1] > 0
			distance[1] -= ai.cols
			ll[1] -= ai.cols unless ll.nil?
		else
			distance[1] += ai.cols
			ll[1] += ai.cols unless ll.nil?
		end
	end
end


def closest_food ant, ai 

	food = ai.food 

	cur_best = nil
	cur_dist = nil

	food.each do |l|
		ll = l.clone

		distance = [ l[0] - ant.row, l[1] - ant.col ]

		norm_distance ai, distance, ll

		dist = distance[0].abs + distance[1].abs

		if !cur_dist || dist < cur_dist
			cur_dist = dist
			cur_best = distance
		end
	end

	cur_best
end

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
			distance = [ sq.row - ant.row, sq.col - ant.col ]
		else
			distance = [ l.row - ant.row, l.col - ant.col ]
		end
		next if l.evading?		# Needed because you can trap an evading ant by following it


		norm_distance ant.ai, distance

		dist = distance[0].abs + distance[1].abs

		# safeguard
		next if dist == 0

		if !cur_dist || dist < cur_dist
			cur_dist = dist
			cur_best = distance
		end
	end

	cur_best
end


def closest_ant l, ai 

	ants = ai.my_ants 

	cur_best = nil
	cur_dist = nil

	ants.each do |ant|

		ll = l.clone

		distance = [ l[0] - ant.row, l[1] - ant.col ]

		norm_distance ai, distance, ll

		dist = distance[0].abs + distance[1].abs

		if !cur_dist || dist < cur_dist
			cur_dist = dist
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

	move ant, best_dir 
end


def move_distance square, distance
	dir = nil

	rdif = distance[0]
	cdif = distance[1]

	if rdif > 0
		rowdir = :S
	else
		rowdir = :N
	end

	if cdif > 0
		coldir = :E
	else
		coldir = :W
	end

	# If one of the directions is zero, choose the other one
	if rdif == 0
		dir = coldir
	elsif cdif == 0
		dir = rowdir
	end
	return dir unless dir.nil?


	# If one of the directions is blocked,
	# and the other isn't, choose the other one
	if !square.neighbor(rowdir).passable?
		if square.neighbor(coldir).passable?
			dir = coldir
		end
	elsif !square.neighbor(coldir).passable?
		if square.neighbor(rowdir).passable?
			dir = rowdir
		end
	end
	
	if dir.nil?
		# Otherwise, choose shortest distance
		if rdif.abs > cdif.abs
			dir = rowdir
		else
			dir = coldir
		end
	end

	dir
end

def move_to ai, from, to
	distance = [ to.row - from.row, to.col - from.col ]
	norm_distance ai, distance
	move_distance from, distance
end

def move ant, dir
	if ant.square.neighbor(dir).passable?
		ant.order dir
	else
		ant.evade dir
	end
end


def get_food ant, ai

	distance = closest_food ant, ai
	return nil unless distance

	move_distance ant.square, distance
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
				move ant, n.moved_to
				done = true
				break
			end
		end
		return true if done


		if has_neighbour
			# Neighbours didn´t move, perform attack yourself
			$logger.info "Attack."
			distance = ant.attack_distance
			dir = move_distance ant.square, distance
			move ant, dir
			return true
		end

		# Find a close neighbour and move to him
		# TODO: following should take moved ant into account
		distance = closest_enemy ant, ant.ai.my_ants 
		unless distance.nil?
			dist = distance[0].abs + distance[1].abs
			if dist == 1 
				$logger.info "next to friend."
				# already next to other ant
				ant.stay
			elsif dist < 20
				$logger.info "Moving to friend."
				dir = move_distance ant.square, distance
				move ant, dir
			end
			return true
		end
end

		# Otherwise, just run away
		$logger.info "Retreat."
		distance = ant.attack_distance
		distance[0] *= -1
		distance[1] *= -1
		dir = move_distance ant.square, distance
		move ant, dir
		return true
	end

	false
end

#
# main routine
#

ai=AI.new

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
#			dir = get_food ant, ai
#			if dir.nil?
#				dir = move_to ai, ant.square, ai.map[ l[0] ][ l[1] ]
#			end
#			move ant, dir
		end
	end 


	ai.my_ants.each do |ant|
		next if ant.moved?

		default_move ant
	end
end
