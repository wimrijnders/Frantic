$:.unshift File.dirname($0)
require 'AI.rb'
require 'BaseStrategy'


#
# main routine
#

strategy = BaseStrategy.new

$ai.setup

$ai.run do |ai|
	strategy.turn ai
end


