class AntObject 
	@@finalize_count = 0
	

    def initialize dummy1, dummy2 = nil, dummy3 = nil, dummy4 = nil
		# Only do this is debug-status mode
		$logger.debug(true) {
        	ObjectSpace.define_finalizer(self,
					self.class.method(:finalize).to_proc)
		}
    end

	# Not called when not in debug 
    def self.finalize(id)
		@@finalize_count += 1

        #$logger.info(true) {  "Object #{id} dying at #{Time.new}" }
    end

	def self.status 
		"Num finalized: #{ @@finalize_count }"
	end
end



def right dir
	newdir = case dir
		when :N; :E 
		when :E; :S 
		when :S; :W 
		when :W; :N 
	end

	newdir
end

def left dir
	newdir = case dir
		when :N; :W 
		when :W; :S 
		when :S; :E 
		when :E; :N 
	end

	newdir
end

def reverse dir
	newdir = case dir
		when :N; :S 
		when :W; :E 
		when :S; :N 
		when :E; :W 
	end

	newdir
end



#
# Determine closest ant by way of view distance.
#
# This is the old style of distance determination and still
# useful when you are only interested in viewing
#
def closest_ant_view l, ai 
	ants = ai.my_ants 

	cur_best = nil
	cur_dist = nil

	ants.each do |ant|
		d = Distance.get ant, l
		dist = d.dist

		if !cur_dist || dist < cur_dist
			cur_dist = dist
			cur_best = ant
		end
	end

	cur_best
end


#
# Following derived from Harvesters
#

def check_spot ai, r,c, roffs, coffs
	if ai.map[ r ][ c ].rel(roffs, coffs).land?
		# Found a spot
		# return relative position
		throw:done, [ roffs, coffs ]
	end
end


def nearest_non_water sq
	return sq if sq.land?

	r = sq.row
	c = sq.col
	rows = sq.ai.rows 
	cols = sq.ai.cols 

		offset = nil
		radius = 1

		offset = catch :done do	

			diameter = 2*radius + 1
			while diameter <= rows or diameter <= cols 
	
				# Start from 12 o'clock and move clockwise

				0.upto(radius) do |n|
					check_spot sq.ai, r, c, -radius, n
				end if diameter <= cols

				(-radius+1).upto(radius).each do |n|
					check_spot sq.ai, r, c, n, radius
				end if diameter <= rows

				( radius -1).downto( -radius ) do |n|
					check_spot sq.ai, r, c, radius, n
				end if diameter <= cols

				( radius - 1).downto( -radius ) do |n|
					check_spot sq.ai, r, c, n, -radius
				end if diameter <= rows

				( -radius + 1).upto( -1 ) do |n|
					check_spot sq.ai, r, c, -radius, n
				end if diameter <= cols

				# End loop
				radius += 1
				diameter = 2*radius + 1
			end
		end

		offset
end

# Only add this when debugging
if AntConfig::LOG_OUTPUT or AntConfig::LOG_STATUS

#
# Count created objects
#
# Source: http://snippets.dzone.com/posts/show/2108
#
class Class
  alias_method :orig_new, :new

  @@count = 0
  @@stoppit = false
  @@class_caller_count = Hash.new{|hash,key| hash[key] = Hash.new(0)}

  def new(*arg,&blk)
    unless @@stoppit
      @@stoppit = true
      @@count += 1
      @@class_caller_count[self][caller[0]] += 1
      @@stoppit = false
    end
    orig_new(*arg,&blk)
  end

  def Class.report_final_tally
	str  = []

	# don't stop; we want interim counts
    #@@stoppit = true
    str << "Number of objects created = #{@@count}"

    total = Hash.new(0)
    
    @@class_caller_count.each_key do |klass|
      caller_count = @@class_caller_count[klass]
      caller_count.each_value do |count|
        total[klass] += count
      end
    end
    
    klass_list = total.keys.sort{|klass_a, klass_b| 
      a = total[klass_a]
      b = total[klass_b]
      if a != b
        -1* (a <=> b)
      else
        klass_a.to_s <=> klass_b.to_s
      end
    }

    klass_list.each do |klass|
		# Don't bother with the small fry
		break if total[klass] < 300

      str << "%7d %20s" % [ total[klass], klass ]

	# Following tells you WHERE in code objects are created
	# very nice, but perhaps overkill for the poor logfiles. 
if false
      caller_count = @@class_caller_count[ klass]
      caller_count.keys.sort_by{|call| -1*caller_count[call]}.each do |call|
        str << "\t#{call}\tCreated #{caller_count[call]} #{klass} objects."
      end
end
    end

	str.join("\n")
  end

end

end
