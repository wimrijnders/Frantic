$:.unshift File.dirname($0)
require 'AI.rb'
require 'BaseStrategy'


#
# main routine
#
$logger.log = false
strategy = BaseStrategy.new

$ai.setup

$ai.run do |ai|
	strategy.turn ai
end


