#!/usr/local/bin/ruby

#
# Configuration options
#

live    = true
bot_num = nil 
turns   = 500 
flags   = "" #--turntime=5000" # "--nolaunch"


#
# Local methods
#

def is_number? a
    true if Integer(a) rescue false
end

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

#
# Main routine
#

if live
	live_opts = " -So | java -jar visualizer.jar"
else
	live_opts = ""
end

map = ARGV[0]
map = map.to_i if is_number? map
puts "Map: #{ map}"

bots = [
	"ruby ../MyBot.rb",		# Frantic
	"python sample_bots/python/GreedyBot.py",
	"ruby ../Inertia.rb",
	"ruby ../GoSouth.rb",
	"ruby ../Twitcher.rb",
	"python2.7 sample_bots/python/HunterBot.py",
	"python submission_test/TestBot.py",
	"python sample_bots/python/LeftyBot.py"
]



if map == 'test'
	mapfile = "submission_test/test.map"
	#flags << " --food none"
elsif map == 'open'
	mapfile  = "open_4_98.map"
elsif map[0] == 'm'
	map = map[1..-1]
	mapfile  = "maze/maze_#{ map }.map"
elsif map[0] == 'h'
	map = map[1..-1]
	map = "0" + map if map.length ==1
	mapfile  = "multi_hill_maze/multi_maze_#{ map }.map"
elsif map[0] == 's'
	map = map[1..-1]
	map = "0" + map if map.length ==1
	mapfile  = "symmetric_random_walk/random_walk_#{ map }.map"
end

bot_num = get_num_players "maps/" + mapfile

fail "Can't handle this map" if bot_num.nil?

system( "python2.7 ./playgame.py --engine_seed 42 --player_seed 42 --end_wait=0.25 --verbose --log_dir game_logs --turns #{ turns } #{ flags } --map_file \"maps/#{ mapfile }\" \"#{ bots[0, bot_num].join( "\" \""  ) }\" -E -I -O#{ live_opts }") 
#system( "python2.7 ./playgame.py --engine_seed 42 --player_seed 42 --end_wait=0.25 --verbose --log_dir game_logs --turns #{ turns } #{ flags } --map_file \"maps/#{ mapfile }\" \"#{ bots[0, bot_num].join( "\" \""  ) }\" -E -I -O --capture_errors#{ live_opts}") 
