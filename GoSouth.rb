$:.unshift File.dirname($0)
require 'AI.rb'
require 'BaseStrategy'


class Strategy < BaseStrategy

	def default_move ant
		ant.move :S
	end
end


#
# main routine
#

strategy = Strategy.new

$ai.setup do |ai|
	# your setup code here, if any
end

$ai.run do |ai|
	# your turn code here
	$logger.info "Start turn."

	strategy.turn ai
	
	$logger.info "End turn."
end


