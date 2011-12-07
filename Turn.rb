
class Turn
	MAX_HISTORY = 10
	CRITICAL_MARGIN = 2

	public

	def initialize turntime, stdout
		@turntime = 1.0*(turntime - AntConfig::TURN_MARGIN)/1000
		@stdout = stdout

		@open = false
		@history = []
		@last_go = Time.now 
	
		# First time send	
		@stdout.puts 'go'
		@stdout.flush
	end


	def maxed_out? 
		history >=  MAX_HISTORY - 3
	end

	def maxed_urgent?
		history >=  CRITICAL_MARGIN
	end


	def check_time_limit
		diff = Time.now - @start

		if diff >= @turnlimit
			$logger.turn(true) { "Hit time limit" }
			throw :maxed_out
		end
	end


	def check_maxed_out
		unless @open
			$logger.turn "throwing :maxed_out"
			throw :maxed_out
		else
			diff = Time.now - @start

			if diff >= @turnlimit
				$logger.turn(true) { "Maxed out!" }
				go @turn, 1
				throw :maxed_out
			end
		end
	end


	def go turn, maxed_out = 0

		$logger.turn(true) { "sending for turn #{ turn }" }
		unless @open
			$logger.turn(true) { "Nothing to send!" }
		else
			@stdout.puts "go"
			@stdout.flush

			@last_go = Time.now
			@open = false
			add_history maxed_out 
		end

	end


	def start turn, diff_gets_d
		start = Time.now
		diff = 0.0
		diff = ((start - @start)*1000).to_i unless @start.nil?
		@start = start

		diff_go = start - @last_go
		diff_go_d = (diff_go*1000).to_i

		diff_gets = 1.0*diff_gets_d/1000

		diff_start_d = ( (start - $logger.start)*1000).to_i

		@turnlimit = @turntime - diff_go + diff_gets
		turnlimit_d  = (@turnlimit*1000).to_i

		$logger.turn(true) { "start #{ diff_start_d } turn: #{ turn } " +
			"limit/go/gets = #{ turnlimit_d }/#{ diff_go_d }/#{ diff_gets_d } " +
			" - maxout #{ hist_to_s }; last call #{ diff }" }

		@turn = turn
		@open = true
	end


	def send str
		ret = true

		if @open
			$logger.turn(true) { "output open." }

			@stdout.puts str 
			@stdout.flush
		else
			$logger.turn(true) { "output closed!" }

			throw :maxed_out
			ret = false
		end

		ret
	end

	def open?
		@open
	end

	private

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


end

