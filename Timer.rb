
class Timer

	def initialize
		clear
		@max = {}
	end

	def start key
		@list[ key ] = [ Time.now, nil, @count ]
		@count += 1

		if block_given?
			yield
			self.end key
		end
	end

	def add_max key, value
		if @max[ key ].nil? or value > @max[ key ]
			@max[ key ] = value
		end
	end

	def end key
		v = @list[ key]
		if v 
			v[1] = Time.now

			value = ( (v[1] - v[0])*1000 ).to_i 

			add_max key, value
		else
			$logger.info { "No start time for #{ key } " }
		end
	end

	def clear
		@list = {}
		@count = 0
	end


	def current key
		v = @list[ key ]
		value = nil
		if v 
			if v[1]
				value = ( ( v[1] - v[0])*1000 ).to_i 
			else
				value = ( ( Time.now - v[0])*1000 ).to_i 
			end
		end

		"Timer #{ key.to_s }: #{value} msec"
	end


	def display
		str = "Timer results (msec):\n";
		start = Time.now
		max_k = nil
		@list.each_pair do |k,v|
			if max_k.nil? or max_k.length < k.length
				max_k = k
			end
		end

		lines = []
		uncomplete = []
		@list.each_pair do |k,v|
			if v[1].nil?
				uncomplete << [k, v]
				next
			end

			value = ( (v[1] - v[0])*1000 ).to_i 
			lines << [ 
				"   %-#{ max_k.length }s %5d %5d" % [ k, value, @max[k] ],
				 v[2]
			]
		end

		lines.sort! { |l1, l2| l1[1] <=> l2[1] }

		str <<
			"   %-#{ max_k.length }s %5s %5s\n" % [ "Label", "Value", "Max" ] <<
			"   %-#{ max_k.length }s %5s %5s\n" % [ "=" * max_k.length , "=" * 5, "=" * 5 ] <<
			lines.transpose[0].join( "\n" ) 

		if uncomplete.length > 0
			tmp = uncomplete.collect {|n| 
				value = ( (start - n[1][0])*1000 ).to_i 
				"#{ n[0] }: #{ value} msec" 
			}
			str << "\nDid not complete:\n   " + tmp.join( "\n   ")
		end

		str
	end


	def get key
		v = @list[ key ]
		unless v.nil?
			endtime = v[1]

			# If the timer did not complete, return a value
			# which is way above the turntime
			if endtime.nil?
				$logger.info { "WARNING: timer #{ key } endtime nil!" }
				2*$ai.turntime
			else
				( (endtime - v[0])*1000).to_i
			end
		else
			nil
		end
	end
end


