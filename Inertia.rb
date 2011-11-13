$:.unshift File.dirname($0)
require 'AI.rb'
require 'BaseStrategy'


#
# main routine
#
$logger.log = false
$logger.log_status = false
strategy = BaseStrategy.new

$ai.run do |ai|
	strategy.turn ai
end


