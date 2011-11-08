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

		super do 
		begin
			# Note the explicit stop here, strictly
			# speaking not necessary but added for start/stop test.
			# threads must be started on creation
			Thread.stop
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



#
# Following definitions used in Patterns
#
# Note that this thread relies heavily on the Patterns context
#
def patterns_thread
		t = Thread.new do
			#Thread.stop
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

				# Only handle last square added
				square = @add_squares.pop
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