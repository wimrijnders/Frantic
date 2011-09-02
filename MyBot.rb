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
	# try to go north, if possible; otherwise try east, south, west.
	[:N, :E, :S, :W].each do |dir|
		if ant.square.neighbor(dir).passable?
			ant.order dir
			break
		end
	end
end

# main routine

ai=AI.new

ai.setup do |ai|
	# your setup code here, if any
end

ai.run do |ai|
	# your turn code here
	
	ai.my_ants.each do |ant|
		closest = closest_food ant, ai.food

		if closest
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

			if ant.square.neighbor(dir).passable?
				ant.order dir
			else
				# given square is occupied. Use original-based code to go somewhere else.	
				default_move ant
			end
		else
			# No closest; just do something
			default_move ant
		end
	end
end
