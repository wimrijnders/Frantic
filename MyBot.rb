$:.unshift File.dirname($0)
require 'ants.rb'

# Local methods

def closest_food ant, food 

	cur_best = nil
	cur_dist = nil

	food.each do |l|
		dist = ( l[0] - ant.row ).abs + (l[1] - ant.col).abs

		if !cur_dist || dist < cur_dist
			cur_dist = dist
			cur_best = l
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

def get_food ant, food
	dir = nil

	closest = closest_food ant, food
	return nil unless closest

	rdif = closest[0] - ant.row
	cdif = closest[1] - ant.col

	if rdif.abs > cdif.abs
		if rdif > 0
			dir = :S
		else
			dir = :N
		end
	else
		if cdif > 0
			dir = :E
		else
			dir = :W
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

		dir = get_food ant, ai.food

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
