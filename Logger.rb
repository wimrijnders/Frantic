
class Logger
	def initialize ai
		@log = AntConfig::LOG_OUTPUT
		@log_status = true
		@@ai = ai
		@start = Time.now

		@f = {}
		@q = []

		@validate = lambda { |log, str, bl|
			# setting str to boolean value 'true' and passing 
			# a block forces override of log inhibition.
			# I use this to output timer info without outputting 
			# regular traces
			return nil unless log or ( str === true and log_status? )

			# don't bother with empty input
			if not str === true 
				return nil if ( not str.nil? and str.length == 0 )
			end

			unless bl.nil?
				str = bl.call
			end

			if str.nil? or str.length == 0
				str = nil
			end
			str
		}
	end

	def q str
		return unless @log

		@q << str
	end

	def all str = nil, &bl
		str = @validate.call @log, str, bl
		return if str.nil?

		method_name = caller_method_name
		@f.keys.each do |k|
			out k, method_name, str
		end
	end

	def stats str = nil, &bl
		str = @validate.call @log, str, bl
		return if str.nil?

		init_logfile "stats" 
		out "stats", caller_method_name, str
	end	


	def info str = nil, &bl
		str = @validate.call @log, str, bl
		return if str.nil?

		thread  = init_logfile

		out thread, caller_method_name, str
	end


	def log= val
		@log = val
	end

	def log?
		@log
	end

	def log_status= val
		@log_status = val
	end

	def log_status?
		@log_status and AntConfig::LOG_STATUS
	end

	private


	def init_logfile name = nil

		if name.nil?
			if Thread.current != Thread.main
				thread = Thread.current[ :name ]
			elsif not Fiber.current.nil?
				thread = Fiber.current[ :name ]
			else 
				thread = "Main"
			end
		else
			thread = name
		end


		if @f[thread].nil?	
			if thread != "Main" 
				filename = "log_#{ thread }.txt"
			else 
				filename = "log.txt"
			end

			@f[ thread ] = File.new( "logs/" + filename, "w")
		end

		thread
	end


	def out file, method_name, str
		time = (Time.now - @start)*1000
		str = "#{ time.to_i } - #{ method_name}: #{ str }"

		while qval = @q.pop
			@f[ file ].write "queue: #{ qval }\n"
		end

		@f[ file ].write str + "\n"
		@f[ file ].flush

		#@@ai.stdout.puts str 
		#@@ai.stdout.flush
	end


	# Source: http://snippets.dzone.com/posts/show/2787
	def caller_method_name
    	parse_caller(caller(2).first).last
	end

	def parse_caller(at)
	    if /^(.+?):(\d+)(?::in `(.*)')?/ =~ at
	        file = Regexp.last_match[1]
			line = Regexp.last_match[2].to_i
			method = Regexp.last_match[3]

		    if /^block.* in (.*)/ =~ method
				method = Regexp.last_match[1]
			end

			[file, line, method]
		end
	end
end

