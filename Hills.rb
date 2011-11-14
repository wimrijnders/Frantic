
class Hills

	def initialize
		@list = {}
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
			@list[key] = owner
			true
		else
			$logger.info { "hill at #{ key } already present." }
			false
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
			@list[key] = -1
		end
	end

	def my_hill? coord
		key = coord[0].to_s + "_" + coord[1].to_s

		if @list[key].nil?
			false
		else
			@list[key] == 0
		end
	end

	def each_enemy
		@list.clone.each_pair do |key, owner|
			# Skip self and dead hills
			next if owner == 0
			next if owner == -1 

			$logger.info { "hill owner #{ owner }" }
			coord = key.split "_"
			coord[0] = coord[0].to_i
			coord[1] = coord[1].to_i

			yield owner, coord
		end
	end


	def each_friend
		@list.clone.each_pair do |key, owner|
			# Skip enemies and dead hills
			next if owner == -1 
			next if owner != 0

			coord = key.split "_"
			coord[0] = coord[0].to_i
			coord[1] = coord[1].to_i

			yield Square.coord_to_square coord
		end
	end

	def each_pair 
		# Adding clone allows to change the @hills
		# within the called block
		@list.clone.each_pair do |key, owner|
			yield key, owner
		end
	end
end