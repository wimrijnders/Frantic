

module AntConfig
	# Testbot config
	NUM_TURNS		= 1500	# Max number of turns per game

	# Tournament runs on Xeon X5675 3.07GHz servers (totaalnet); bogomips: 6117.71
	# My laptop is a Core 2 Duo SU7300 1.3GHz; bogomips: 2678.11
	# So server is 2.28 times faster

	TURN_TIME		= 1150	# Num msec per bot per turn

	# Num msec safety margin for handling turn
	TURN_MARGIN		= 200   # This value for the tournament
	#TURN_MARGIN		= 350   # This value for testing. 


	LOG_OUTPUT      = false
	LOG_STATUS      = false	# if LOG_OUTPUT is false, log status info only

	DEFENSIVE_LIMIT = 20	# Number of ants needed to be present
							# before ants start attacking as well

	AGGRESIVE_LIMIT = 30	# At this number, the ant will
							# choose fights sooner 

	ANALYZE_LIMIT	= 40	# After this number of ants, analyze will
							# give preferences to hurting instead of
							# playing safe

	THROTTLE_LIMIT  = 150

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

