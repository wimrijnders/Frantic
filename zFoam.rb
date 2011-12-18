$:.unshift File.dirname($0)
require 'AI.rb'
require 'BaseStrategy'


#
# main routine
#
$logger.log = false
$logger.log_status = false
strategy = BaseStrategy.new

	def move_away list
		ant = list[-1]

		return false if ant.moved?


		dirs = [ :N, :E, :S, :W ].sort_by! { rand }
if false
		if $hill.nil? or $hill == ant.square
			dirs = [ :N, :E, :S, :W ].sort_by! { rand }
		else
			# prefer to move away from the hill
			d = Distance.new $hill, ant.square
			dir = d.longest_dir
			dirs = [ dir ]
			dirs += [ left(dir), right(dir) ].sort_by! { rand }
			dirs << reverse( dir )

if false
			unless d.shortest_dir.nil?
				dirs << d.shortest_dir
			else
				dirs << [ left(d.dir), right(d.dir) ][ rand(2) ]
			end
			dirs.sort_by! { rand }
end
		end
end

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


	def num_neighbors ant
		count = 0 
		[ :N, :E, :S, :W ].each do |dir|
			count += 1 if ant.square.neighbor(dir).ant?
		end

		count
	end

#
# Main loop
#

$ai.run do |ai|


	# Attempt to move away if too many neighbors
	ai.my_ants.each do |ant|
		next if ant.moved?

		enemy = ant.closest_enemy
		if not enemy.nil?
			ant.set_order enemy.square, :ATTACK
		elsif num_neighbors( ant) > 0
			move_away [ ant]
		end
	end


	# Attempt to move off the hill if there
	ai.hills.each_friend do |sq|
		$hill = sq

		if sq.ant? and sq.ant.mine? and not sq.ant.moved?
			move_away [ sq.ant]
		end
	end

	strategy.turn ai
end


