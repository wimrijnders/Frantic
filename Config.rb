

module AntConfig
	# Testbot config
	NUM_TURNS		= 1000	# Max number of turns per game
	TURN_TIME		= 2000	# Num msec per bot per turn


	LOG_OUTPUT      = true
	LOG_STATUS      = true	# if LOG_OUTPUT is false, log status info only

	DEFENSIVE_LIMIT = 20	# Number of ants needed to be present
							# before ants start attacking as well

	AGGRESIVE_LIMIT = 30	# At this number, the ant will
							# choose fights sooner 

	ANALYZE_LIMIT	= 60	# After this number of ants, analyze will
							# give preferences to hurting instead of
							# playing safe

	THROTTLE_LIMIT  = 130 

	KAMIKAZE_LIMIT  = -1	# There's too many ants, getting close to
							# timeout. Take extreme measures to bring
							# down the population 
							# -1 for no limit

	FOOD_LIMIT      = 5     # Max number of food items per turn
							# for which to do path searches

	HARVEST_LIMIT	= 30	# Harvesting starts at this number of
							# ants

	# Stuff for collectives

	ASSEMBLE_LIMIT = 10		# Number of ants in game before we 
							# start to assemble collectives

	ASSEMBLY_LIMIT = 30		# Number of turns to wait until giving 
							# up on assembly


	SAFE_LIMIT       = 5 	# Disband if there was no threat
							# to the collective for given number of moves

	INCOMPLETE_LIMIT = 15	# Disband if could not assemble collective for
							# given number of moves

	FIGHT_DISTANCE   = 20	# If not attacked and enemy detected within
							# given distance, move there to pick a fight
end

