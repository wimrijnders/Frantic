#!/usr/local/bin/ruby
require 'thread'
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

	def inc_yields
		@yields = 0	if @yields.nil?

		@yields += 1
	end

	def yields
		@yields = 0	if @yields.nil?

		@yields
	end

	class << self
		alias :prev_yield :yield

		def yield
			Fiber.current.inc_yields
			prev_yield
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
		@status = :init

		@fiber = Fiber.new do
			run_fiber
		end
		@fiber[ :name ] = name 
	end

	def status 
		@status
	end

	def stats
		[  @name, @status.to_s, @count, @fiber.yields  ]
	end

	def run_fiber
		begin
			longest_diff = nil
			longest_count = nil

			doing = true
			while doing
				$logger.info "waiting"
				while list.length == 0
					@status = :waiting
					Fiber.yield
				end

				count = 0
				start = Time.now
				@status = :running
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
						longest_diff = diff
						longest_count = count

					end

					str = " Longest: #{ longest_count } in #{ longest_diff } msec"

					"added #{ count } results in #{ diff} msec. #{ str }" 
				}

			end

			@status = :done
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


class RegionsFiber < WorkerFiber
	def initialize region, list
		super("regions", region, list)
	end

	def action source
		$logger.info { "finding regions for #{ source }" }
		@region.find_regions source 
		$patterns.fill_map source 
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
		list = @list.clone

		while list.length > 0 
			list.clone.each { |f|
				# run at least once, to be able to reset the state
				f.resume

				if f.status == :waiting or f.status == :done
					list.delete f
					next
				end

			}

			$ai.turn.check_maxed_out
		end
	end


	def status
		format1 = "%10s %8s %7s %7s\n"
		format  = "%10s %8s %7d %7d\n"
		str = "Fibers:\n" +
			format1 % [ "Name      ", "status  ", "  count", "yields" ] +
			format1 % [ "==========", "========", "  =====", "======" ]

		@list.each { |f|
			str << format % f.stats
		 }

		str
	end
end
