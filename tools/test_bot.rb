#!/usr/local/bin/ruby

def is_number? a
    true if Integer(a) rescue false
end

bot_num = nil 
turns = 100 
flags = "" #"--turntime=20000" # "--nolaunch"

map = ARGV[0]
map = map.to_i if is_number? map


map2 = {
	'test' => "submission_test/test.map"
}

map4 = [ 
	'blank', 10,11,16,
	21, # big, open map! Coll2+4 should have won
	23, 28,
	36 # to beat
]

map5 = [
	4,
	8,
	35	# to beat
]

bots = [
	"ruby ../MyBot.rb",		# Frantic
	"ruby ../Twitcher.rb",
	"ruby ../GoSouth.rb",
	"ruby ../Inertia.rb",
	"python sample_bots/python/HunterBot.py",
	"python sample_bots/python/GreedyBot.py",
	"python sample_bots/python/GreedyBot.py",
	"python sample_bots/python/GreedyBot.py",
	"python submission_test/TestBot.py"
]
# "python sample_bots/python/LeftyBot.py"


if map2.member? map
	bot_num = 2
	mapfile = map2[ map ]
	flags << " --food=none"		# Needed for asymmetric maps
end

bot_num = 4 if map4.member? map
bot_num = 5 if map5.member? map

mapfile  = "maps/symmetric_maps/symmetric_#{ map }.map" unless mapfile

fail "Can't handle this map" if bot_num.nil?

system( "python2.7 playgame.py --player_seed=42 --engine_seed=42  --end_wait=0.25 --verbose --log_dir game_logs --turns #{ turns } -O -E -e #{ flags } -m \"#{ mapfile }\" \"#{ bots[0, bot_num].join( "\" \""  ) }\"")

# --food none
# --strict
# --capture_errors
