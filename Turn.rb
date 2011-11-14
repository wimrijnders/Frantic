
class Turn
	MAX_HISTORY = 10
	CRITICAL_MARGIN = 2

	public

	def initialize turntime, stdout
		margin = 250 

		@turntime = 1.0*(turntime - margin)/1000
		@stdout = stdout

		@buffer = {} 
		@history = []
	
		# First time send	
		@stdout.puts 'go'
		@stdout.flush
	end


	def maxed_out? 
		history >=  MAX_HISTORY - 2
	end

	def maxed_urgent?
		history >=  CRITICAL_MARGIN
	end



	def check_maxed_out
		if @buffer[ @turn ].nil?
			$logger.turn "throwing :maxed_out"
			throw :maxed_out
		else
			diff = Time.now - @start

			if diff >= @turntime
				$logger.turn(true) { "Maxed out!" }
				go @turn
				throw :maxed_out
			end
		end
	end


	def go turn

		$logger.turn(true) { "sending for turn #{ turn }" }
		if @buffer[ turn ].nil?
			$logger.turn(true) { "Nothing to send!" }
		else
		
			@stdout.puts @buffer[ turn ]

			@stdout.puts "go"
			@stdout.flush

			@buffer.delete( turn  ) {
				$logger.turn(true) { "ERROR: buffer not deleted." }
			}
		end

	end


	def start turn
		start = Time.now
		diff = 0.0
		diff = start - @start unless @start.nil?
		@start = start

		$logger.turn(true) { "output open turn  #{ turn } - time from previous open: #{ (diff*1000).to_i }" }
		@turn = turn
		@buffer[turn] = ""

		#@wait.signal
		#Thread.pass
	end

	def send str
		ret = true

		unless @buffer[ @turn ].nil?
			$logger.turn(true) { "output open." }
			@buffer[ @turn ] << str + "\n"
		else
			$logger.turn(true) { "output closed!" }

			throw :maxed_out
			ret = false
		end

		ret
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
