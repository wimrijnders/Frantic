class Hill
	COUNTER_LIMIT = 5

	attr_accessor :active
	attr_reader :owner


	def initialize owner
		$logger.info "initialized hill owner #{ owner}"
		@owner = owner
		@active = true

		@counter = 0
	end

	def set_dead
		$logger.info "Hill died"
		@owner = -1
	end


	def should_raze?
		# Skip self and dead hills
		unless @owner != 0 and @owner != -1
			false
		else
			if @counter <= 0
				$logger.info { "Resetting hill counter owner #{ @owner }" }
				@counter = COUNTER_LIMIT

				true
			else
				@counter -= 1
				false
			end
		end
	end
end


class Hills

	def initialize
		@list = {}
	end

	def start_turn
		@list.each_value {|v| v.active = false }
	end

	#
	# Add new hill coord
	#
	# Return: true if added, false if already present
	#
	def add owner, coord
		key = coord[0].to_s + "_" + coord[1].to_s

		if @list[key].nil?
			$logger.info { "Adding hill at #{ key }." }
			@list[key] =  Hill.new owner
			true
		else
			$logger.info { "hill at #{ key } already present." }
			@list[key].active =  true
			false
		end
	end


	def active? coord
		key = coord[0].to_s + "_" + coord[1].to_s

		unless @list[key].nil?
			@list[key].active
		else
			nil
		end
	end


	#
	# Declare a hill as dead.
	#
	# It is not removed, because it could possible reappear in the input.
	# instead the owner is set to -1.
	#
	def remove coord
		key = coord[0].to_s + "_" + coord[1].to_s

		if @list[key].nil?
			$logger.info { "Hill at #{ key } not present, can't remove." }
		else
			$logger.info { "Removing hill on #{ key } from list" }
			@list[key].set_dead
		end
	end

	def my_hill? coord
		key = coord[0].to_s + "_" + coord[1].to_s

		if @list[key].nil?
			false
		else
			@list[key].owner == 0
		end
	end


	def hill? square
		key = square.row.to_s + "_" + square.col.to_s
		not @list[key].nil?
	end

	
	def key_to_coord key
		coord = key.split "_"
		coord[0] = coord[0].to_i
		coord[1] = coord[1].to_i

		coord
	end
	

	def each_enemy
		@list.clone.each_pair do |key, item|
			next unless item.should_raze?

			owner = item.owner

			$logger.info { "hill owner #{ owner }" }

			yield owner, key_to_coord( key )
		end
	end


	def each_friend
		@list.clone.each_pair do |key, item|
			owner = item.owner

			# Skip enemies and dead hills
			next if owner == -1 
			next if owner != 0

			yield Square.coord_to_square( key_to_coord( key ) )
		end
	end


	def each_pair 
		# Adding clone allows to change the @hills
		# within the called block
		@list.clone.each_pair do |key, item|
			owner = item.owner

			yield key, owner
		end
	end
end
