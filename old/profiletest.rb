require 'ruby-prof'

 # Profile the code
  RubyProf.start

def bla
puts "Hello bla!"
end

(0..100).each do

bla
end



 result = RubyProf.stop

  # Print a flat profile to text
  printer = RubyProf::FlatPrinter.new(result)
  #printer.print(STDOUT)
  printer.print( File.new("profile.txt", "w") )
