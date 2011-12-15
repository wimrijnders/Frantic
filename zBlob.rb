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

		return if ant.moved?

		if ant.stuck?
			$logger.info "#{ ant } stuck!"

			# Signal other ants to move away
			dirs = [ :N, :E, :S, :W ].sort_by! { rand }

			dirs.each do |dir|
				ant2 = ant.square.neighbor( dir ).ant
				if ant2 and
				   ant2.mine? and
				   not ant2.moved? and
				   not list.include? ant2
			
					move_away list + [ ant2 ]	
				end
			end
		end

		if not ant.stuck?
			sq = ant.square 

			[ :N, :E, :S, :W ].each do |dir|
				if sq.neighbor(dir).passable?
					$logger.info "Moving #{ ant} to #{ dir }" 
					ant.move dir
					break
				end
			end

			return
		end
	end


$ai.run do |ai|

	strategy.turn ai

	# Attempt to move off the hill if there
	ai.hills.each_friend do |sq|
		if sq.ant? and sq.ant.mine?
			move_away [ sq.ant]
		end
	end

end


