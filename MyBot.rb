$:.unshift File.dirname($0)
require 'ants.rb'

# Local methods

def closest_food ant, ai 

	food = ai.food 

	cur_best = nil
	cur_dist = nil

	food.each do |l|
		ll = l.clone

		rowdist = l[0] - ant.row
		coldist = l[1] - ant.col

		# If the distance is greater than half the width/height,
		# try the other side of the torus
		if rowdist.abs > ai.rows/2
			if rowdist > 0
				rowdist -= ai.rows
				ll[0] -= ai.rows
			else
				rowdist += ai.rows
				ll[0] += ai.rows
			end
		end

		if coldist.abs > ai.cols/2
			if coldist > 0
				coldist -= ai.cols
				ll[1] -= ai.cols
			else
				coldist += ai.cols
				ll[1] += ai.cols
			end
		end

		dist = rowdist.abs + coldist.abs

		if !cur_dist || dist < cur_dist
			cur_dist = dist
			cur_best = ll
		end
	end


	cur_best
end


def default_move ant
	moved = false

	# try to go north, if possible; otherwise try east, south, west.
	[:N, :E, :S, :W].each do |dir|
		if ant.square.neighbor(dir).passable?
			ant.order dir
			moved = true
			break
		end
	end

	unless moved
		ant.stay
	end
end

def get_food ant, ai
	dir = nil

	closest = closest_food ant, ai
	return nil unless closest

	rdif = closest[0] - ant.row
	cdif = closest[1] - ant.col

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

	# If one of the directions is blocked,
	# and the other isn't, choose the other one
	if !ant.square.neighbor(rowdir).passable?
		if ant.square.neighbor(coldir).passable?
			dir = coldir
		end
	elsif !ant.square.neighbor(coldir).passable?
		if ant.square.neighbor(rowdir).passable?
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



#
# main routine
#

ai=AI.new

ai.setup do |ai|
	# your setup code here, if any
end

ai.run do |ai|
	# your turn code here
	
	ai.my_ants.each do |ant|
		next if ant.evading

		dir = get_food ant, ai

		unless dir.nil?
			if ant.square.neighbor(dir).passable?
				ant.order dir
			else
				ant.evade dir
			end
		else
			# No food close by; just do something
			default_move ant
		end
	end
end
