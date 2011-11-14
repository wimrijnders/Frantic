#!/usr/local/bin/ruby
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

				while list.length > 0
					# Handle next item
					action list.pop

					count += 1
					@count += 1
					Fiber.yield
				end

				doing = !done_loop

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
		false
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
		false
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


class PatternsFiber < WorkerFiber
	def initialize patterns, list
		super("patterns", patterns, list)

		patterns.init_tasks
	end


	def action square
		# Confusion arbitrator...
		patterns = @region 

		# Only handle last square added with known region
		unless square.done_region
			while square = @list.pop
				break if square.done_region
			end
		end
		@list.clear

		return  if square.nil?

		$logger.info { "Got square #{ square}" }
		patterns.show_field square
		patterns.match_tests square
	end


	def done_loop
		# Confusion arbitrator...
		patterns = @region 

		if patterns.all_confirmed
			$logger.info "No more open tests; yay, we're done!"
			true
		else
			false
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
		@list << $patterns.init_fiber

		self
	end


	def resume
		list = @list.clone

		while list.length > 0 
			list.clone.each { |f|
				# Remove done fibers immediately
				if f.status == :done
					list.delete f
					next
				end

				# run at least once, to be able to reset the state
				f.resume

				if f.status == :waiting 
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
