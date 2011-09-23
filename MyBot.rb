$:.unshift File.dirname($0)
#######################################
# TODO
#
# - Attacking collective: if only blocked by non-water, stay instead of evade.
# - Staying put is a good strategy for small playing fields.
# - 1-x ant combat; best approach is diagonal on corner ant. You die but you also kill one enemy.
# - On evasion, select shortest route (fast-forward?)
# - Break off evasion if under attack for collectives
# - Creating collectives: don't do it in the direct neighbourhood of water (fixed obstacles) 
#
# - URGENT! collective attack: 
#		- break flip-flop deadlock 
#		- detect ants which ignore you and keep on going in the same direction
#		- defensive: detect inert enemies, these render you immobile.
#
# - If attacked with no way of escape, defend as well as possible
#		- if ant is sure to die, let him take an enemy down
# - Retreat: for multiple attackers, select good escape route
#
# - BUG: Following appearing in the logs:
#
#   - 87756: collective3 ( 55, 82 ) relpos count: 3, orient: n # unknown action
#
#   Ie. one member too many TODO: Fix
#
# DOING
#
# - URGENT: Timeout problem because of sorting enemy ants.
#            TODO: NEEDS TO BE FIXED
#
# - Assembling collective: if new ants are made closer by than assembling ants,
#     use these new ants instead
#     	- ideal case: in exact necessary position
#
#######################################

ENABLE_PROFILING = false
NUM_TURNS 		 = 265

require 'AI.rb'
require 'BaseStrategy'


if ENABLE_PROFILING
	require 'ruby-prof'

	 # Profile the code
	RubyProf.start
end


class Strategy < BaseStrategy

	def recruit ant
	
		# recruit near neighbours for a collective
		if ant.ai.defensive?
			friend_distance = 10
		else
			friend_distance = 20
		end
	
		recruits = ant.neighbor_friends friend_distance 
		recruits.delete_if { |a| a.collective? }
	
		# If there are enough, make the collective
		if recruits.size > 0 
			recruits.each do |l|
				ant.add_collective l, recruits.length
				break if ant.collective_assembled?
			end
			$logger.info "Created collective #{ ant.collective.to_s}"
		else
			# If not enough close by, disband the collective
			# These may then be used for other incomplete collectives
			catch :done do
				ant.collective.disband if ant.collective?
			end
		end
	end
	
	

	def default_move ant
		return if ant.moved?
	
		directions = [:N, :E, :S, :W, :N, :E, :S, :W ]
	
		# go to the least visited square
		best_visited = nil
		best_dir = nil
		
		# Select preferred direction as longest direction on map.
		# This fills the map up faster with following approach
		index = 0
		if ant.ai.rows < ant.ai.cols
			index = 1
		end
	
		( directions[ index, 4] ).each do |dir|
			sq = ant.square.neighbor( dir )
		
			next unless sq.passable?
		
			val = sq.visited
			if !best_visited || val < best_visited
				best_visited = val
				best_dir = dir
			end
		end
		
		best_dir = directions[ index ] if best_dir.nil?
		
		ant.move best_dir 
	end



	#
	# Complete existing collectives first
	#
	def complete_collectives ai
		ai.my_ants.each do |ant|
			next unless ant.collective?
			next if ant.collective.assembled? false
	
			recruit ant
		end
	
	end


	#
	# Assemble new collectives
	#
	def create_collectives ai
		ai.my_ants.each do |ant|
			next if ant.collective?
	
			next unless ant.attacked? 
	
			# Don't even think about assembling if not enough ants around
			next if ant.ai.my_ants.length < AntConfig::ASSEMBLE_LIMIT
	
			if ant.ai.defensive? 
				# If collective nearby, don't bother creating a new one
				collective_near = false
				ant.neighbor_friends( 10 ).each do |a|
					if a.collective?
						$logger.info "#{ ant.square.to_s } has collective nearby"
						collective_near = true
						break
					end
				end
	
				next if collective_near
			end
	
			# If too close too an assembling collective, 
			# don't bother creating a new one
			collective_near = false
			ant.neighbor_friends( 3 ).each do |a|
				if a.collective?
					$logger.info "#{ ant.square.to_s } assembling collective too close "
					collective_near = true
					break
				end
			end
			next if collective_near
	
			recruit ant
		end
	end


	#
	# Handle non-collective ants which are in a conflict situation
	#
	def ant_conflict ai
		ai.my_ants.each do |ant|
			next if ant.collective?
			ant.handle_conflict
		end
	end



	def move_collectives ai	
		# Move collectives as a whole
		ai.my_ants.each do |ant|
			next unless ant.collective_leader?
	
			ant.move_collective
		end
	end


	def turn ai
		check_attacked ai	
		complete_collectives ai
		create_collectives ai unless ( ai.my_ants.length >= AntConfig::KAMIKAZE_LIMIT )
		ant_conflict ai
		ant_orders ai
		move_collectives ai

		super ai, false, ( ai.my_ants.length < AntConfig::KAMIKAZE_LIMIT )
	end
end


#
# main routine
#

strategy = Strategy.new

$ai.setup

$ai.run do |ai|
	# your turn code here
	$logger.info "Start turn."

	strategy.turn ai
	
	$logger.info "End turn."

	if ENABLE_PROFILING
		# Need to put this within the loop, otherwise 
		# no output is generated. I think this is something
		# to do with how IO is handled by the calling program
		#
		# Turn number should ideally be next to last. This
		# can't be determined while the program is running.
		#
		# -2 because zero-based and we want next-to-last turn.
		#
		if ai.turn_number == NUM_TURNS - 2
			result = RubyProf.stop
		
			#printer = RubyProf::FlatPrinter.new(result)
			printer = RubyProf::GraphPrinter.new(result)
			#printer.print(STDOUT)
			printer.print( File.new("profile4.txt","w"))
		
			$logger.info "Profiling done."
		end
	end
end


