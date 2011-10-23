

module Evasion
	@@curleft = true

	@want_dir = nil
	@next_dir = nil


	def evade_init
		@left = @@curleft
		@@curleft = !@@curleft
	end

	def evade_reset
		@want_dir = nil
		@next_dir = nil
	end

	def evade_dir dir
		if @left
			left dir
		else 
			right dir
		end
	end

	def evade2_dir dir
		if @left
			right dir
		else 
			left dir
		end
	end


	def evading?
		!@next_dir.nil?
	end


	def evade dir
		# The direction we want to go is blocked;
		# go round the obstacle
		$logger.info { "#{ self.to_s} starting evasion" if @want_dir.nil? }
	
		done = false
		newdir = dir

		# Don't try original direction again
		(0..2).each do
			newdir = evade_dir newdir

			# can_pass? is supplied by the encompassing class
			if can_pass? newdir
				done = true
				break
			end
		end
	
		if done
			@want_dir = dir if @want_dir.nil?
			@next_dir = evade2_dir newdir
			order newdir
		else
			# stay is supplied by the encompassing class
			stay
		end
	end


	def evading
		unless @next_dir.nil?
			$logger.info { "evading next_dir" }

			if can_pass? @next_dir
				order @next_dir

				# if the direction went corresponds with the
				# direction wanted, we are done.
				if @next_dir == @want_dir
					$logger.info { "evasion complete" }
					@next_dir = nil
					@want_dir = nil
				else
					@next_dir = evade2_dir @next_dir
				end
			else 
				evade @next_dir
			end

			return true
		end

		false
	end
end

