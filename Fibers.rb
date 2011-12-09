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
	attr_accessor :status

	def now
		Timer.now
	end


	def resume 
		start = now

		@fiber.resume 

		diff = now - start
	
		if @max_resume < diff
			@max_resume = diff
		end
	end

	def initialize name, region, list
		@name = name
		@region = region
		@list = list
		@turn = 0

		@count = 0
		@status = :init
		@max_resume = 0.0 

		@fiber = Fiber.new do
			run_fiber
		end
		@fiber[ :name ] = name 
	end

	def stats
		[  @name, @status.to_s, @count, @fiber.yields, (@max_resume*1000).to_i, list.length  ]
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
				start = now
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
					diff = ( (now - start)*1000 ).to_i

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

if false
		# TODO: check if this absolutely necessary
		skip_count = 0
		while skip_count < 10
			$logger.info { "handling path: #{ path }" }
			item = @region.get_path_basic path[0], path[-1]
			unless item.nil?
				$logger.info { "path item already there" }

				if item[:path] == path
					$logger.info { "path is the same; skipping" }
					skip_count += 1
					return if list.empty?
					path = list.pop # NOTE: list is accessed directly here
					next
				end
			end
			break
		end
		return if skip_count >= 10
		Fiber.yield
end

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


#
# Fiber to preprocess and filter searches for the two search threads,
# to offload the computation from the main program.
#
# Gains are absolutely minimal, but what the hey. Every msec counts.
#
class SelectSearch < WorkerFiber
	@@list = []
	@@q_cache= {}

	def initialize
		super("select", $region, @@list )
	end

	def self.add_list item
		@@list << item
	end

	def action item
		from, to_list, do_shortest, max_length =item

		sq_ants   = Region.ants_to_squares to_list

		$logger.info {
			"handling search #{ from }-#{ sq_ants }, " +
			"#{ do_shortest }, #{max_length}"
		}

		# Don't bother with empty input 
		return if from.nil? or from.region.nil?
		return if sq_ants.nil? or sq_ants.length == 0

		# Convert input to regions
		from_r = from.region
		to_list_r = Region.squares_to_regions sq_ants
		to_list_r.compact!

		# Don't bother with targetting from-region
		to_list_r.delete from_r

		if to_list_r.length == 0
			$logger.info "to_list_r empty or same as from, not searching."
			return 
		end
		to_list_r.sort!		# To make comparing list easier downstream 

		item = [ from_r, to_list_r, do_shortest, max_length]

		if not max_length.nil? and max_length == -1
			$logger.info { "Doing big search" }
			BigSearch.add_list item
		else
			Fiber2.add_list item 
		end
	end
end


class BigSearch< WorkerFiber
	@@list = []
	@@q_cache= {}

	def initialize
		super("BigSearch", $region, @@list )
	end

	def self.add_list item
		if @@q_cache[ item]
			# NOTE: This does not seem to be happening!
			$logger.info { "big search #{item} already queued" }
		else
			@@q_cache[ item] = true
			@@list << item
		end
	end

	def action item
		from_r, to_list_r, do_shortest, max_length = item 

		$logger.info { "searching regions #{ from_r }-#{ to_list_r }" }

		# Results will be cached within this call
		@region.find_paths from_r, to_list_r, do_shortest, max_length
	end
end



class Fiber2 < WorkerFiber
	@@list = []
	@@q_cache= {}

	def initialize
		super("fiber2", $region, @@list)
	end

	def self.add_list item
		if @@q_cache[ item]
			$logger.info { "search #{item} already queued" }
		else
			@@q_cache[ item] = true
			@@list << item
		end
	end


	def action item
		from_r, to_list_r, do_shortest, max_length = item 

		$logger.info { "searching regions #{ from_r }-#{ to_list_r }" }

		# Results will be cached within this call
		tmp = @region.find_paths from_r, to_list_r, do_shortest, max_length
		if tmp.nil?
			$logger.info "No results; retrying search as big search"
			BigSearch.add_list [ from_r, to_list_r, do_shortest,  -1 ]
		end
	end
end


class RegionsFiber < WorkerFiber
	def initialize region, list
		super("regions", region, list)
	end

	def action source
		$logger.info { "finding regions for #{ source }" }
		@region.find_regions source 

		Fiber.yield

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


class BorderPatrolFiber < WorkerFiber

	@@list = []
	@@obj = BorderPatrol.new
	@@found_hills = false

	def initialize
		super("borderpatrol", $region, @@list)
	end

	def action source
		$logger.info { "doing action #{ source }" }
		unless source == "go"
			if @@obj.clear_liaison source
				@@list << "go"	# Note that this allows double (perhaps even more) go's in list
			end
		end
		if @@obj.action
			@@list << "go"
		end
	end


	def self.add_list item
		@@list << item
	end


	def self.init_hill_regions
		return if @@found_hills

		$ai.hills.each_friend do |sq| 
			@@found_hills = true

			@@obj.add_hill_region sq 
		end

		if @@found_hills
			$logger.info "got the hills"
			@@list << "go"
			return
		end
	end

	def self.request_target sq
		@@obj.next_liaison sq
	end

	def self.clear_target sq
		BorderPatrolFiber.add_list sq
	end

	def self.known_region sq
		@@obj.known_region sq.region
	end
end


class Fibers

	def initialize
		@list = []

		self
	end

	def init_fibers
		@list += [
			SelectSearch.new,
			Fiber2.new,
			BigSearch.new,
			BorderPatrolFiber.new
		]
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

				begin 
					if f.kind_of? SelectSearch  and f.status != :waiting
						$logger.info "giving priority 1 to SelectSearch"

						while f.status != :waiting
							f.resume
							$ai.turn.check_time_limit
						end
					elsif f.kind_of? Fiber1  and f.status != :waiting
						$logger.info "giving priority 2 to Fiber1"

						while f.status != :waiting
							f.resume
							$ai.turn.check_time_limit
						end
					else
						f.resume
						$ai.turn.check_time_limit
					end

				rescue FiberError
					$logger.info(true) { "Thread probably died...." }
					# Help it out of its misery
					f.status = :done
					list.delete f
					next
				end

				if f.status == :waiting 
					list.delete f
					next
				end

			}

			#$logger.info { "End loop list length: #{ list.length }" }
		end

		#$logger.info { "End" }
	end


	Format1 = "%12s %8s %7s %7s %5s %7s\n"
	Format  = "%12s %8s %7d %7d %5d %7d\n"
	def status
		str = "Fibers:\n" +
			Format1 % [ "Name        ", "status  ", "  count", "yields", "  max", "queue" ] +
			Format1 % [ "============", "========", "  =====", "======", "=====", "=====" ]

		@list.each { |f|
			str << Format % f.stats
		 }

		str
	end
end
