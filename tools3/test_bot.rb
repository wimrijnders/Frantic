#!/usr/local/bin/ruby

#
# Configuration options
#

live    = true
bot_num = nil 
turns   = 1000 
flags   = "--turntime=5000" # "--nolaunch"


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
nump = ARGV[1]
num = ARGV[2]
nump = "0" + nump if nump and  nump.length ==1
num = "0" + num if num and num.length ==1

map = map.to_i if is_number? map


bots = [
	"ruby ../MyBot.rb",					# Frantic - latest version
	"ruby ../GoSouth.rb",
	"python sample_bots/python/GreedyBot.py",
	"python2.7 sample_bots/python/HunterBot.py",
	"ruby ../GoSouth.rb",
	"ruby ../Twitcher.rb",
	"ruby ../Inertia.rb",
	"ruby ../frantic03/MyBot.rb",		# Frantic - previous version
	"python sample_bots/python/LeftyBot.py",
	"python2.7 sample_bots/python/HunterBot.py",
	"python submission_test/TestBot.py"
]



if map == 'test'
	mapfile = "submission_test/test.map"
	#flags << " --food none"
elsif map == 'open'
	mapfile  = "maps/open_4_98.map"
elsif map[0] == 'm'
	map = "0" + map if map.length ==1
	mapfile  = "maps/maze/maze_#{nump}p_#{ num }.map"
elsif map[0] == 'h'
	map = "0" + map if map.length ==1
	mapfile  = "maps/multi_hill_maze/maze_#{ nump }p_#{ num }.map"
elsif map[0] == 'r'
	map = "0" + map if map.length ==1
	mapfile  = "maps/random_walk/random_walk_#{ nump }p_#{ num }.map"
end

puts "Map: #{ mapfile }"
bot_num = get_num_players mapfile

fail "Can't handle this map" if bot_num.nil?

system( "python2.7 ./playgame.py --engine_seed 42 --player_seed 42 --end_wait=0.25 --verbose --log_dir game_logs --turns #{ turns } #{ flags } --map_file \"#{ mapfile }\" \"#{ bots[0, bot_num].join( "\" \""  ) }\" -E -I -O#{ live_opts }") 
