#!/usr/local/bin/ruby
require 'thread'
require 'timeout'

require 'fiber'

class Fiber

	def []= arg, value

		@hash = {} if @hash.nil?

		@hash[arg] = value
	end

	def [] arg
		@hash = {} if @hash.nil?
		@hash[arg]
	end
end



class Mutex

	def set_wait
		@wait = ConditionVariable.new
	end

	def signal
		@wait.signal
		Thread.pass
	end

	# Don't call your input param 'timeout'. It interferes with
	# the timeout module definition.
	def waitlock period
if false
		begin		
			Timeout::timeout(period) {
				#self.lock
				@wait.wait self
			}

			$logger.info "Got the lock"
			true
		rescue Timeout::Error
			$logger.info "KABLOOEY!!!!"
			return false
		end
end

		start = Time.now	
		@wait.wait self, period
		if Time.now - start < period
			$logger.info "Got the lock"
			true
		else
			@wait.signal	# WRI DEBUG
			$logger.info "KABLOOEY!!!!"
			false
		end
	end

	def try_unlock
		begin
			unlock
			true
		rescue ThreadError
			$logger.info "Lock not mine"
			false
		end
	end
end


#
# Following definitions used in Region
#

class WorkerFiber 

	def resume; @fiber.resume; end

	def initialize name, region, list
		@name = name
		@region = region
		@list = list
		@turn = 0

		@count = 0
		@longest_count = 0
		@longest_diff = 0

		@fiber = Fiber.new do
			run_fiber
		end
		@fiber[ :name ] = name 
	end

	def status
		[  @name, @count, @longest_count, @longest_diff ]
	end

	def run_fiber
		begin
			longest_diff = nil
			longest_count = nil

			doing = true
			while doing
				$logger.info "waiting"
				while list.length == 0
					Fiber.yield
				end

				count = 0
				start = Time.now
				init_loop

$logger.info "Running fiber loop"
$timer.start("fibre") {

				while list.length > 0
					# Handle next item
					action list.pop

					count += 1
					@count += 1
					Fiber.yield
				end
}
$logger.info "Done fiber loop"

				done_loop

				$logger.info {
					diff = ( (Time.now - start)*1000 ).to_i

					if longest_diff.nil? or diff > longest_diff
						@longest_diff = diff
						@longest_count = count

					end

					str = " Longest: #{ @longest_count } in #{ @longest_diff } msec"

					"added #{ count } results in #{ diff} msec. #{ str }" 
				}

			end

			$logger.info "closing down."
		end rescue $logger.info( "Boom! #{ $! }\n #{ $!.backtrace }" )
	end

	def list
		@list
	end


	def init_loop
	end


	def done_loop
	end
end

class WorkerThread < Thread

	#
	# Tryout to see if threads can start and stop between themselves
	# Doesn't work, because threads don't restart.
	#
	def self.start_next name
		return false

		foundit = false
		Thread.list.each { |t|
			if t[ :name ] == name 
				$logger.info "starting #{name}"
				t.run
				foundit = true
				break
			end
		}

		Thread.stop
		$logger.info "restarted"
		#foundit
	end

	def initialize name, region, list
		@region = region
		@list = list
		@turn = 0

		super do 
		begin
			Thread.current[ :name ] = name 

			$logger.info "activated"

			longest_diff = nil
			longest_count = nil

			doing = true
			while doing
				$logger.info "waiting"
				while list.length == 0
					sleep 0.2
				end

				count = 0
				start = Time.now
				init_loop
				while list.length > 0
					# Handle next item
					action list.pop

					count += 1
				end
				done_loop

				$logger.info {
					diff = ( (Time.now - start)*1000 ).to_i

					if longest_diff.nil? or diff > longest_diff
						longest_diff = diff
						longest_count = count

					end

					str = " Longest: #{ longest_count } in #{ longest_diff } msec"

					"added #{ count } results in #{ diff} msec. #{ str }" 
				}

			end

			$logger.info "closing down."
		end rescue $logger.info( "Boom! #{ $! }\n #{ $!.backtrace }" )
		end
	end

	def list
		@list
	end


	def init_loop
	end


	def done_loop
	end
end


#class Thread1 < WorkerThread
class Fiber1 < WorkerFiber
	def initialize region, list
		super("fiber1", region, list)
	end

	def init_loop
		@new_count, @known_count, @replaced_count = 0, 0, 0 
	end

	def action path

		return if path.length == 0

		$logger.info { "saving path: #{ path }" }
		# Cache the result
		new_tmp, known_tmp, replaced_tmp = @region.set_path path
		@new_count      += new_tmp
		@known_count    += known_tmp
		@replaced_count += replaced_tmp

		new_tmp, known_tmp, replaced_tmp = @region.set_path path.reverse
		@new_count      += new_tmp
		@known_count    += known_tmp
		@replaced_count += replaced_tmp
	end

	def done_loop
		$logger.info {
			"new: #{ @new_count}, known: #{ @known_count }, replaced: #{ @replaced_count }"
		}
	end
end


class BigSearch< WorkerFiber
	def initialize region, list
		$logger.info "Initializing BigSearch"
		super("BigSearch", region, list)
	end

	def action item

		from, to_list, do_shortest, max_length = item 

		$logger.info { "searching #{ from }-#{ to_list }" }

		# Results will be cached within this call
		@region.find_paths from, to_list, do_shortest, max_length
	end
end


class Fiber2 < WorkerFiber

	def initialize region, list
		super("fiber2", region, list)
		@add_search = []
	end

	def my_list
		@add_search
	end

	def action item

		from, to_list, do_shortest, max_length = item 

		if not max_length.nil? and max_length ==-1
			$logger.info "Offloading big search"
			if @add_search.length > 0
				$logger.info "Already have big search in queue, skipping"
			else
				@add_search << item
			end
			return
		end

		if from.nil?
			$logger.info(true) { "ERROR from item is nil; skipping" }
			return
		end

		$logger.info { "searching #{ from }-#{ to_list }" }

		# Results will be cached within this call
		@region.find_paths from, to_list, do_shortest, max_length
	end
end


class RegionsThread < WorkerThread
	def initialize region, list
		super("FindRegions", region, list)
	end

	def action source
		$logger.info { "finding regions for #{ source }" }
		@region.find_regions source 
		$patterns.fill_map source 

		# WorkerThread.start_next "Thread2"
	end
end


def patterns_thread
		t = Thread.new do
			Thread.current[ :name ] = "Patterns"
			$logger.info "activated"

			@radius = ( ai.viewradius/Math.sqrt(2) ).to_i

			$logger.info "viewradius2: #{ ai.viewradius2 }"
			$logger.info "radius: #{ @radius }"

			init_tasks

			doing = true
			while doing

				$logger.info "waiting"
				while @add_squares.length == 0
					sleep 0.2 
				end

				# Only handle last square added with known region
				while square = @add_squares.pop
					break if square.done_region
				end
				next if square.nil?
				@add_squares.clear

				$logger.info { "Got square #{ square}" }
				show_field square

				match_tests square


				# Loop exit condition; no more tests to do.

				all_confirmed = true 
				@tests.each do |t|
					unless t.confirmed
						all_confirmed = false
						break
					end
				end
				if all_confirmed
					$logger.info "No more open tests; yay, we're done!"
					doing = false
				end

				#if WorkerThread.start_next "FindRegions"
			end rescue $logger.info( "Boom! #{ $! }\n #{ $!.backtrace }" )

			$logger.info "closing down."
		end
		t.priority = -3
end



class TurnThread < Thread
	MAX_HISTORY = 10
	CRITICAL_MARGIN = 2

	def add_history val
		@history << val
		if @history.length > MAX_HISTORY
			@history = @history[1..-1]
		end
	end


	def history
		sum = 0
		@history.each { |h| sum += h }

		sum
	end

	def hist_to_s
		"#{ history }/#{ @history.length }"	
	end

	def maxed_out? 
		history >=  MAX_HISTORY - 2
	end

	def maxed_urgent?
		history >=  CRITICAL_MARGIN
	end

	def initialize loadtime, turntime, stdout
		@mutex = Mutex.new
		@mutex2 = Mutex.new
		@mutex.set_wait
		@wait = ConditionVariable.new

		margin = 250 

		@turntime = 1.0*(turntime - margin)/1000
		@loadtime = 1.0*(loadtime - margin)/1000
		@stdout = stdout

		@buffer = {} 
		@history = []
	
		# First time send	
		@stdout.puts 'go'
		@stdout.flush
 
		t = super do 
		begin
			Thread.current[ :name ] = "Turn" 

			$logger.info "activated"

			@mutex.lock

			doing = true
			while doing

				$logger.info(true) { "waiting...."	}
				
				@wait.wait @mutex

				turn = @turn
				$logger.info(true) { "Counting turn #{ turn}: #{ hist_to_s }" }
				start = Time.now

				# For first turn use loadtime instead
				if turn == 0
					$logger.info { "doing loadtime #{ @loadtime }" }
					max = @loadtime
				else 
					max = @turntime
				end

				success = @mutex.waitlock max

				if not success 
					$logger.info(true) { "Maxed out!" }
					if turn == @turn
						go turn
					else
						$logger.info(true) {
							"ERROR: turn changed #{ turn } => #{ @turn}" 
						}

						# Send anyway; the server is waiting for a response
						go turn
					end
					add_history 1 
				else
					diff = Time.now - start

					$logger.info(true) {
						"sent in time: #{ (diff*1000).to_i } msec"
					}
					add_history 0 
				end
			end

			$logger.info "closing down."
		end rescue $logger.info( "Boom! #{ $! }\n #{ $!.backtrace }" )
		end
		t.priority = 1
	end


	def go turn
@mutex2.synchronize {

		# Do the signal before, so that thread is informed as early as possible 

		unless Thread.current[ :name ] == "Turn" 
			@mutex.signal
		end

		$logger.info(true) { "sending for turn #{ turn }" }
		if @buffer[ turn ].nil?
			$logger.info(true) { "Nothing to send!" }
		else
		
			@stdout.puts @buffer[ turn ]

if false
			# Hold out as long as you can, to give the helper threads
			# as much time as possible to do their stuff
			diff = Time.now - @start - 0.1
			if diff > 0
				$logger.info { "Holding out for #{ (diff*1000).to_i } msec" }
				sleep diff
			end
end

			@stdout.puts "go"
			@stdout.flush

			@buffer.delete( turn  ) {
				$logger.info(true) { "ERROR: buffer not deleted." }
			}
		end

}
	end


	def start turn
		start = Time.now
		diff = 0.0
		diff = start - @start unless @start.nil?
		@start = start

		$logger.info(true) { "output open turn  #{ turn } - time from previous open: #{ (diff*1000).to_i }" }
		@turn = turn
		@buffer[turn] = ""

		@wait.signal
		Thread.pass
	end

	def send str
@mutex2.synchronize {
		ret = true

		unless @buffer[ @turn ].nil?
			$logger.info(true) { "output open." }
			@buffer[ @turn ] << str + "\n"
		else
			$logger.info(true) { "output closed!" }

			throw :maxed_out
			ret = false
		end

		ret
}
	end

	def check_maxed_out
		if @buffer[ @turn ].nil?
			$logger.info "throwing :maxed_out"
			throw :maxed_out
		end
	end
end


class Fibers

	def initialize
		@list = []

		self
	end

	def init_fibers
		@list += $region.init_fibers

		self
	end

	def resume
		@list.each { |f| f.resume }
	end

	def status
		format1 = "%10s %5s %7s %5s\n"
		format = "%10s %5d %7d %5d\n"
		str = "Fibers:\n" +
			format1 % [ "Name      ", "count", "    max", "diff" ] +
			format1 % [ "==========", "=====", "=======", "====" ]

		@list.each { |f|
			str << format % f.status
		 }

		str
	end
end
