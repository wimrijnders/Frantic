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

$ai.setup

$ai.run do |ai|
	strategy.turn ai
end


