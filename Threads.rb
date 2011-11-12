#
# Following definitions used in Region
#

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
		end rescue $logger.info( "Boom! #{ $! }" )
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


class Thread1 < WorkerThread
	def initialize region, list
		super("Thread1", region, list)
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


class BigSearchThread < WorkerThread
	def initialize region, list
		$logger.info "Initializing BigSearchThread"
		super("BigSearchThread", region, list)
	end

	def action item

		from, to_list, do_shortest, max_length = item 

		$logger.info { "searching #{ from }-#{ to_list }" }

		# Results will be cached within this call
		@region.find_paths from, to_list, do_shortest, max_length

		#WorkerThread.start_next "Patterns"
	end
end


class Thread2 < WorkerThread

	def initialize region, list
		super("Thread2", region, list)
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
			$logger.info "ERROR from item is nil; skipping"
			return
		end

		$logger.info { "searching #{ from }-#{ to_list }" }

		# Results will be cached within this call
		@region.find_paths from, to_list, do_shortest, max_length

		#WorkerThread.start_next "Patterns"
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


class PointsThread < WorkerThread
	# Region is a misnomer; here it is actually the PointCache instance
	def initialize region, list
		super("Points", region, list)
	end

	def action source
		pointcache = @region

		from = source[0]
		to = source[1]
		$logger.info "Handling #{from}-#{to}"
	
		pointcache.retrieve_item from, to, nil, true
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
			end rescue $logger.info "Boom! #{ $! }"

			$logger.info "closing down."
		end
		t.priority = -3
end


def liaisons_thread
		t = Thread.new do
			Thread.current[ :name ] = "liaisons"
			$logger.info "activated"

			squares = []
			(0...$ai.rows).each do |row |
				(0...$ai.cols).each do |col|
					squares << [ $ai.map[ row][col], nil ]
				end
			end

			while squares.length > 0

				$logger.info "waiting"
				sleep 0.2 

				count = 0
				squares.clone.each do |item|
					sq = item[0]

					if sq.water?
						squares.delete item
						count+= 1
						next
					end

					next if sq.region.nil?

					if item[1].nil?
						liaisons = $region.get_liaisons sq.region

						if liaisons.nil? or liaisons.length == 0
							next
						end

						item[1] = liaisons.values
					end

					$logger.info "testing #{ item }"

					item[1].clone.each do |l|
						if sq == l
							item[1].delete l
							next
						end

						if $pointcache.get(sq, l, true ).nil? 
							$pointcache.retrieve_item sq, l, true
						elsif $pointcache.get(l, sq, true ).nil? 
							$pointcache.retrieve_item l, sq, true
						else
							item[1].delete l
							next
						end
					end
	
					if item[1].length == 0 
						$logger.info "Found all liaisons for #{ sq}"
						squares.delete item
						count += 1
					end

				end
				$logger.info "Found #{count} items. to go: #{ squares.length}"

			end rescue $logger.info "Boom! #{ $! }"

			$logger.info "closing down."
		end
		t.priority = -3
end



class TurnThread < Thread
	MAX_HISTORY = 10
	CRITICAL_MARGIN = 3

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
		history >=  CRITICAL_MARGIN
	end

	def initialize loadtime, turntime, stdout
		margin = 200 

		@turntime = 1.0*(turntime - margin)/1000
		@loadtime = 1.0*(loadtime - margin)/1000
		@stdout = stdout

		@open = false
		@buffer = {} 
		@history = []
	
		# First time send	
		@stdout.puts 'go'
		@stdout.flush
 
		t = super do 
		begin
			Thread.current[ :name ] = "Turn" 

			$logger.info "activated"

			doing = true
			while doing
				unless @open
					$logger.info "waiting"
					while not @open 
						sleep 0.001
					end
				end

				$logger.info(true) { "Counting #{ hist_to_s }" }
				start = Time.now
				turn = @turn
				diff = 0.0

				# For first turn use loadtime instead
				if turn == 0
					$logger.info(true) { "doing loadtime #{ @loadtime }" }
					max = @loadtime
				else 
					max = @turntime
				end

				while @open and turn == @turn and diff < max 
					#sleep 0.001
					Thread.pass
					diff = Time.now - start
				end 

				if turn != @turn
					$logger.info(true) {
						"turn changed #{ turn } => #{ @turn}"
					}
				end

				if diff >= max 
					$logger.info(true) { "Maxed out!" }
					if turn == @turn
						go turn
					else
						$logger.info(true) { "Different turn; not daring to send" }
					end
					add_history 1 
				else
					$logger.info(true) {
						"sent in time: #{ (diff*1000).to_i } msec"
					}
					add_history 0 
				end
			end

			$logger.info "closing down."
		end rescue $logger.info( "Boom! #{ $! }" )
		end
		t.priority = 1
	end

	def go turn
#Thread.exclusive {
		@open = false

		$logger.info(true) { "sending for turn #{ turn }" }
		if @buffer[ turn ].nil?
			$logger.info(true) { "Nothing to send!" }
			return
		end

		
		@stdout.puts @buffer[ turn ]
		@stdout.puts "go"
		@stdout.flush

		@buffer.delete turn 
#}
	end

	def start turn
		if @open 
			$logger.info "ERROR: Output already open!"
			return
		end

		$logger.info "output open"
		@turn = turn
		@open = true
		@buffer[turn] = ""
	end

	def send str
		if @open
			$logger.info "output open."
			@buffer[ @turn ] << str + "\n"
			true
		else
			$logger.info "output closed!"

			# Concurrency problems with following
			# TODO: sort it out
			#throw :maxed_out
			false
		end
	end
end

