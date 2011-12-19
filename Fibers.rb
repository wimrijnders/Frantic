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

		def init
			@root_fiber = Fiber.current
			$logger.info "Root fiber: #{ @root_fiber }"
		end

		def yield
			if Fiber.current != @root_fiber
				Fiber.current.inc_yields
				prev_yield
			end
		end

		def current?
			Fiber.current == @root_fiber
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

module WorkerQueue

	# This is the way to include class methods from a mixin module.
	# Amazingly, I can't find this call in the ruby docs.
	def self.included(base)
		base.extend ClassMethods
	end

  module ClassMethods

		# Note that we are using class instance variables,
		# not class static variables!

		def init
			@list = []	if @list.nil?
			@q_cache= {} if @q_cache.nil?
		end

		#
		# return true if item added, false otherwise
		#
		def add_list item
			init

			if @q_cache[ item]
				$logger.info { "#{ name } #{item} already queued" }
				false
			else
				@q_cache[ item] = true
				@list << item
				true
			end
		end

		def list
			init

			@list
		end
	end
end


class Fiber1 < WorkerFiber
	include WorkerQueue

	def initialize
		super("fiber1", $region, Fiber1.list)
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


#
# Fiber to preprocess and filter searches for the two search threads,
# to offload the computation from the main program.
#
# Gains are absolutely minimal, but what the hey. Every msec counts.
#
class SelectSearch < WorkerFiber
	include WorkerQueue

	def initialize
		super("select", $region, SelectSearch.list )
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
		$logger.info { "item #{ item }" }

		if not max_length.nil? and max_length == -1
			$logger.info { "Doing big search" }
			BigSearch.add_list item
		else
			Fiber2.add_list item 
		end
	end
end




class BigSearch< WorkerFiber
	include WorkerQueue

	def initialize
		super("BigSearch", $region, BigSearch.list )
	end


	def action item
		from_r, to_list_r, do_shortest, max_length = item 

		$logger.info { "searching regions #{ from_r }-#{ to_list_r }" }

		# Results will be cached within this call
		@region.find_paths from_r, to_list_r, do_shortest, max_length
	end
end



class Fiber2 < WorkerFiber
	include WorkerQueue

	def initialize
		super("fiber2", $region, Fiber2.list)
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
	include WorkerQueue

	def initialize
		super("regions", $region, RegionsFiber.list)
	end

	def action source
		$logger.info { "finding regions for #{ source }" }
		@region.find_regions source 

		Fiber.yield

		$patterns.fill_map source 
	end
end


class PatternsFiber < WorkerFiber
	include WorkerQueue

	def initialize
		# NB: Patterns instance passed to instance var named @region!
		#	  This is a potential source of confusion.
		super("patterns", $patterns, PatternsFiber.list)

		$patterns.init_tasks
	end


	# Confusion resolver.
	def patterns
		@region
	end

	def action square
		# Only handle last square added with known region, ignore
		# rest of queue
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
		if patterns.all_confirmed
			$logger.info "No more open tests; yay, we're done!"
			true
		else
			false
		end
	end
end


class WalkFiber < WorkerFiber
	# WorkerQueue intentionally not mixed in.
	@@list = []

	def self.add_list item
		@@list << item
	end

	def initialize
		super("walk", $region, @@list)
	end

	def action item
		from, to = item

		$pointcache.set_walk from, to, to, true, true
	end
end


class BorderPatrolFiber < WorkerFiber
	# WorkerQueue not mixed in.
	# This is intentional; there can be multiple 'go'
	# instructions in the queue, these should not be filtered
	# for uniqueness.

	@@list = []
	@@obj = BorderPatrol.new
	@@found_hills = false


	def self.add_list item
		@@list << item
	end

	def initialize
		super("borderpatrol", $region, @@list)
	end

	def action source
		$logger.info { "doing action #{ source }" }
		@@obj.clear_liaison source

		@@obj.action if @@list.empty?
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

	def self.request_target sq, skip_regions
		@@obj.next_liaison sq, skip_regions
	end

	def self.clear_target sq
		BorderPatrolFiber.add_list sq
	end

	def self.known_region sq
		@@obj.known_region sq.region
	end

	def self.get_center region
		@@obj.get_center region
	end

	def self.num_exits region
		@@obj.num_exits region
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
			BorderPatrolFiber.new,
			Fiber1.new,
			RegionsFiber.new,
			PatternsFiber.new,
			WalkFiber.new
		]

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
					# Counters give some breathing space to other
					# fibers; SelectSearch and Fiber1 have a tendency to
					# completely take over fiber run time.
					if f.kind_of? SelectSearch
						count = 0
						begin
							f.resume

							if count == 0 and f.status == :running
								$logger.info "giving priority 1 to SelectSearch"
							end

							count += 1

							$ai.turn.check_time_limit
						end while f.status == :running and count < 200

					elsif f.kind_of? Fiber1 
						count = 0
						begin
							f.resume

							if count == 0 and f.status == :running
								$logger.info "giving priority 2 to Fiber1"
							end

							count += 1

							$ai.turn.check_time_limit
						end while f.status == :running and count < 100
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
