#!/usr/local/bin/ruby

def is_number? a
    true if Integer(a) rescue false
end

bot_num = nil 
turns = 150 
flags = "" #"--turntime=20000" # "--nolaunch"

map = ARGV[0]
map = map.to_i if is_number? map

# Nice symmetric maps to test 
# These are now not part of the code, btw.

maps = [ 
	'blank', # 4pl, no water at all
	21, 	 # 4pl,  big, open map! Coll2+4 should have won
			 # Good one for using the test bots
	36, 	 # 4pl, to beat
	35		 # 5pl to beat
]


# End maps

bots = [
	"ruby ../MyBot.rb",		# Frantic
	"ruby ../GoSouth.rb",
	"ruby ../Twitcher.rb",
	"ruby ../Inertia.rb",
	"python sample_bots/python/GreedyBot.py",
	"python sample_bots/python/HunterBot.py",
	"python submission_test/TestBot.py",
	"python sample_bots/python/LeftyBot.py"
]


def get_num_players mapfile
	file = File.new( mapfile, "r")
	while (line = file.gets)
		if line =~ /^players/
			tmp = line.split(" ")
			num = tmp[1]
			break
		end
	end
	file.close

	num.to_i
end

if map == 'test'
	mapfile = "submission_test/test.map"
	flags << " --food=none"
elsif map == 'blank'
	mapfile  = "maps/symmetric_maps/symmetric_#{ map }.map"
elsif map[0] == 'a'
	map = map[1..-1]

	mapfile  = "maps/asymmetric_maps/asymmetric_#{ map }.map"
	flags << " --food=none"		# Needed for asymmetric maps - This makes testing of asymmetric maps useless
elsif map[0] == 's'
	map = map[1..-1]
	mapfile  = "maps/symmetric_maps/symmetric_#{ map }.map"
elsif map[0] == 'h'
	map = map[1..-1]
	mapfile  = "maps/height_maps/height_map_#{ map }.map"
elsif map[0] == 'o'
	map = map[1..-1]
	mapfile  = "maps/octagonal_maps/octagonal_#{ map }.map"
end

bot_num = get_num_players mapfile

fail "Can't handle this map" if bot_num.nil?

system( "python2.7 playgame.py --player_seed=42 --engine_seed=42  --end_wait=0.25 --verbose --log_dir game_logs --turns #{ turns } -O -E -e #{ flags } -m \"#{ mapfile }\" \"#{ bots[0, bot_num].join( "\" \""  ) }\"")

# --food none
# --strict
# --capture_errors
