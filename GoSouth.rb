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
strategy = Strategy.new

$ai.setup do |ai|
	$region = Region.new ai
	Pathinfo.set_region $region
end

$ai.run do |ai|
	strategy.turn ai
end


