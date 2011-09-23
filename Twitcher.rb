$:.unshift File.dirname($0)
require 'AI.rb'
require 'BaseStrategy'


class Strategy < BaseStrategy

	def initialize
		@curdir = :E
	end

	def default_move ant
		ant.move @curdir
	end

	def turn ai
		super ai
		@curdir = (@curdir== :E )? :W: :E 
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


