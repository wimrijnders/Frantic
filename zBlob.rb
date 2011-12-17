$:.unshift File.dirname($0)
require 'AI.rb'
require 'BaseStrategy'


#
# main routine
#
$logger.log = true
$logger.log_status = false
strategy = BaseStrategy.new

	def move_away list
		ant = list[-1]

		return false if ant.moved?

		dirs = [ :N, :E, :S, :W ].sort_by! { rand }
		tmp = []
		dirs.each do |dir|
			n = ant.square.neighbor( dir )
			if n.passable? false
				tmp << dir
			end
		end
	
		tmp.each do |dir|	
			n = ant.square.neighbor( dir )
			unless n.passable? 
				ant2 = n.ant

				if ant2 and
				   ant2.mine? and
				   not ant2.moved? and
				   not list.include? ant2
			
					move_away list + [ ant2 ]	
				end
			end

			if n.passable? 
				ant.move dir
				return true
			end
		end

		ant.stay
		return false 
	end


$ai.run do |ai|

	strategy.turn ai

	ai.my_ants.each do |ant|
		next if ant.moved?
		enemy = ant.closest_enemy
		unless enemy.nil?
			ant.set_order enemy.square, :ATTACK
			next
		end
	end

	# Attempt to move off the hill if there
	ai.hills.each_friend do |sq|
		if sq.ant? and sq.ant.mine?
			move_away [ sq.ant]
		end
	end

end


