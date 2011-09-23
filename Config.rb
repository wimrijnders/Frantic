

module AntConfig

	LOG_OUTPUT      = true	# Output logging info to stdout

	DEFENSIVE_LIMIT = 20	# Number of ants needed to be present
							# before ants start attacking as well

	ASSEMBLE_LIMIT = 10		# Number of ants in game before we 
							# start to assemble collectives

	# Stuff for collectives

	SAFE_LIMIT       = 5 	# Disband if there was no threat
							# to the collective for given number of moves

	INCOMPLETE_LIMIT = 15	# Disband if could not assemble collective for
							# given number of moves

	FIGHT_DISTANCE   = 20	# If not attacked and enemy detected within
							# given distance, move there to pick a fight
end

