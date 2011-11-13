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

$logger.log = false
$logger.log_status = false
strategy = Strategy.new

$ai.run do |ai|
	strategy.turn ai
end


