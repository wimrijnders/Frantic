#!/usr/local/bin/ruby
require '../Config'

#
# Configuration options
#

live    = true
bot_num = nil 
turns   = AntConfig::NUM_TURNS 
flags   = "--nolaunch --turntime=#{ AntConfig::TURN_TIME }" #-R


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
	live_opts = " -So | java -Xms1536m -Xmx1536m -jar visualizer.jar"
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
	"ruby ../zBlob2.rb",
	"ruby ../zBlob.rb",
	"ruby ../zFoam2.rb",
	"ruby ../zFoam.rb",

	"ruby ../MyBot.rb",					# Frantic - latest version

	"ruby ../frantic20/MyBot.rb",

	"ruby ../zGoSouth.rb",
	"ruby ../zFoam.rb",
	"ruby ../zBlob.rb",
	"ruby ../zTwitcher.rb",

	"ruby ../frantic17/MyBot.rb",
	"ruby ../frantic05/MyBot.rb",
	"ruby ../frantic13/MyBot.rb",
	"ruby ../frantic04/MyBot.rb",
	"ruby ../frantic03/MyBot.rb",

	"python2.7 sample_bots/python/HunterBot.py",
	"python sample_bots/python/GreedyBot.py",
	"python sample_bots/python/LeftyBot.py",
	"python submission_test/TestBot.py"
]

#
# Good test maps:
# c 2 6 - smallest 2-player cell map
#


if map == 'test'
	mapfile = "submission_test/test.map"
elsif map == 'open'
	mapfile  = "maps/open_4_98.map"
elsif map == 'm'
	mapfile  = "maps/maze/maze_#{nump}p_#{ num }.map"
elsif map == 'mp'
	mapfile  = "maps/maze/maze_p#{nump}_#{ num }.map"
elsif map == 'c'
	mapfile  = "maps/cell_maze/cell_maze_p#{nump}_#{ num }.map"
elsif map == 'h'
	mapfile  = "maps/multi_hill_maze/maze_#{ nump }p_#{ num }.map"
elsif map == 'r'
	mapfile  = "maps/random_walk/random_walk_#{ nump }p_#{ num }.map"
elsif map == 'rp'
	mapfile  = "maps/random_walk/random_walk_p#{ nump }_#{ num }.map"
end

puts "Map: #{ mapfile }"
bot_num = get_num_players mapfile

fail "Can't handle this map" if bot_num.nil?

system( "python2.7 ./playgame.py --engine_seed 42 --player_seed 42 --end_wait=0.25 --verbose --log_dir game_logs --turns #{ turns } #{ flags } --map_file \"#{ mapfile }\" \"#{ bots[0, bot_num].join( "\" \""  ) }\" -E -I -O#{ live_opts }") 
