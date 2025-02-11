#!/usr/bin/env ruby

require 'optparse'
require "yaml"
require "fileutils"
require 'readline'
require 'dentaku'

$version_string = "calc 3.0a\nCopyright 2009-2025 Chris Biagini"

$usage = <<USAGE
Usage
  Enter an expression and press Enter. Results are automatically saved as
  variables which can be used directly in later expressions. To name a
  variable yourself, use the '=' operator: '$my_variable = 1 + 1'.

Commands
  help            Shows this message.
  list            Shows the current contents of memory and list of saved 
                  memory files.
  delete $var     Deletes the named variable.
  delete all      Deletes all variables in memory.
  save [name]     Saves the contents of memory to a file.
  restore [name]  Restores the contents of memory from a file.
  clear           Clears the screen.
  quit            Quits the program.
  
Special Variables
  $_              Results of the last expression.
USAGE

# exit politely on interrupt (^C)
trap("SIGINT") do
  puts ""
  exit
end

class Memory
  protected

    attr_reader :memory_hash, :auto_variable_name
  
    # Copy the data from another Memory object into the current one
    def absorb(new_memory)
      @memory_hash = new_memory.memory_hash
      @auto_variable_name = new_memory.auto_variable_name      
    end
  
  public
  
    def initialize
      @memory_hash = Hash.new   # this mess is all just a wrapper for Hash
      @auto_variable_name = 1   # index for automatically assigned variables
    end
  
    # Store a variable into memory with an optional name
    # * automatically assigns a name if passed nil
    # * returns whatever name the variable winds up getting
    def store(variable_name, value)
      if variable_name.nil? then
        variable_name = @auto_variable_name.to_s
        @auto_variable_name += 1
      end
    
      @memory_hash[variable_name] = value
      return variable_name
    end
    
    # Updates the +$_+ variable
    def update_last(value)
     @memory_hash["_"] = value
    end
    
    # Saves contents of memory to a YAML file in "~/.cli-calc/"
    # * saved in +default+ if +savefile+ is +nil+
    def save(savefile)
      data_dir = File.expand_path("~/.cli-calc/") + "/"
      FileUtils.mkdir_p(data_dir)
      
      if savefile.nil? then
        savefile = "default"
        custom = false
      else
        custom = true
      end
      
      File.open(data_dir + savefile, 'w') do |file|
        YAML.dump(self, file)
      end
      
      return "Saved contents of memory to '#{savefile}'." if custom == true
      return "Saved contents of memory." if custom == false
    end

    # Loads contents of memory from a YAML file in "~/.cli-calc/"
    # * loaded from +default+ if +savefile+ is +nil+    
    def load(savefile)
      if savefile.nil? then
        savefile = "default"
        custom = false
      else
        custom = true
      end
      
      new_memory = YAML.load_file(File.expand_path("~/.cli-calc/") + "/" + savefile)
      
      self.absorb(new_memory)
      
      return "Restored contents of memory from '#{savefile}'." if custom == true
      return "Restored contents of memory." if custom == false
    end
  
    # Lists all the variables for which the user has given a name
    def named_variables
      @memory_hash.keys.delete_if{|key| key =~ /^[0-9]+$/}.map{|item| "$" + item}
    end
    
    # Lists all the saved files
    def savefiles
      begin
        entries = Dir.entries(File.expand_path("~/.cli-calc/"))
        entries.delete(".")
        entries.delete("..")
        return entries      
      rescue SystemCallError
         return [] 
      end
    end
  
    # Recursively looks up and substitutes variables in a given expression
    def substitute_variables(expression, recursions=0)
      subbed = false
      
      # if the user is doing an expression that requires more than 100 lookups,
      # he should be using a better tool than this silly thing
      if recursions > 100 then
        raise(StandardError, "Error: Possible infinite recursion. Check your variables for a circular reference")
      end
      
      # smart enough to not try to sub $10 if there's no value for $10, 
      # but no escaping say, $1 until Ruby has negative lookbehinds or I 
      # come up with something clever. For now, just using "$ 1" to mean 
      # "1 dollar" works just fine.      
      expression.gsub!(/\$([0-9A-Za-z_]+)/) do
        $name = $1
    
        if @memory_hash[$name].nil? then
          $& # value of whole match, in case query was something like "$480 in UK pounds"
        else
          subbed = true
          @memory_hash[$name]
        end    
      end
      
      return substitute_variables(expression, recursions + 1) if subbed == true    
      return expression
    end
  
    # Lists current contents of memory. Could use a better name.
    def dump
      return "  Memory is empty." if @memory_hash.empty?
    
      sorted_array = @memory_hash.sort
    
      memory_table = ""
    
      sorted_array.each do |memory_pair|
        memory_table << "  $" + memory_pair[0].to_s + " = " + memory_pair[1].to_s + "\n"
      end
    
      return memory_table
    end
  
    # Deletes a variable from memory
    def delete(variable_name)
      result = @memory_hash.delete(variable_name)
      raise "Variable $#{variable_name} does not exist" if result.nil?
    end
  
    # Deletes all variables from memory
    def clear
      @memory_hash = Hash.new
      @auto_variable_name = 1
    end
end

# Actually looks up results from Google. Could maybe fall back to bc on error?
def do_calculation(expression)
  calculator = Dentaku::Calculator.new
  calculator.evaluate(expression)
end


# Set up command line options
opts = OptionParser.new
opts.on("-?", "-h", "--help", "Show this message") { puts opts; exit }
opts.on("-v", "--version", "Display version and copyright information") { puts $version_string; exit }
opts.on("-q", "--quiet", "Do not display banner at startup") { $quiet = true }
opts.on("-e", "--expression expression", "Evaluate expression (non-interactive)") do |expression|
  begin
    puts do_calculation(expression)
  rescue StandardError => msg
      STDERR.puts msg
  end

  exit  
end
opts.on("--about", "Show detailed info about this program") { RDoc::usage }

begin 
  opts.parse(ARGV)
rescue OptionParser::ParseError => msg
  puts msg
  puts opts
  exit
end

memory = Memory.new
    
# build array of autocompletion targets, rejecting blank and comment lines
targets = DATA.read.split(/\n/).delete_if {|x| x =~ /(^[ \t]*#)|(^[ \t]*$)/ }

Readline.basic_word_break_characters = Readline.basic_word_break_characters.sub(/\$/, '')
Readline.completion_append_character = " "

# build autocomplete function
Readline.completion_proc = proc do |input|
  targets = targets + memory.named_variables + memory.savefiles

  regex = Regexp.new("(?i)^" + input.gsub(/\$/, '\$'))
  targets.find_all { |target| target =~ regex }
end

if (!$quiet) then
  puts $version_string
  puts ""
end

# loop forever or until told otherwise
while true

  # read a line
  command = Readline.readline("? ", true).strip.gsub(/\t/, " ")
  
  case command
    when /^$/             # ignore blank input
      next
    
    when /^(clear|cs)$/           # clear screen
      print "\e[H\e[2J"
    
    when /^(q|quit|exit)$/  # quit
      break
    
    when /^(help|wtf)$/         # display summary of usage notes
      puts $usage
      puts ""
      
    when /^save *(.+)?$/         # save contents of memory
      begin
        message = memory.save($1)
        puts "  " + message
      rescue StandardError => msg
        STDERR.puts "  Error saving contents of memory: " + msg + "."
      end
      puts ""
            
    when /^(?:restore|load) *(.+)?$/      # restore memory from saved file
      begin
        message = memory.load($1)
        puts "  " + message
      rescue StandardError => msg
        STDERR.puts "  Error restoring memory from file: " + msg + "."
      end
      puts ""

    when /^(list|ls)$/        # displays list of saved memory files
      puts memory.dump

      puts ""

      files = memory.savefiles
      
      if files.nil? or files.count == 0
        puts "  There are no saved memory files."
      else
        puts "  Saved memory files in ~./cli-calc:"
        puts memory.savefiles.map{|file| "    " + file}
      end
    puts ""

    when /^delete +all$/   # delete all variables
      memory.clear
      puts "  All variables deleted."
      puts      

    when /^delete +\$?(.+)$/   # delete single variable
      begin
        memory.delete($1)
        puts "Variable $#{$1} deleted."
      rescue StandardError => msg
        STDERR.puts "  #{msg}."
      end
    puts ""
      
    when /^\$([0-9A-Za-z_]+) *<= *(.+)$/   # assignment without evaluation
      variable_name = $1
      value = $2
      memory.store(variable_name, value)
      puts "  $#{variable_name} = #{value}"
      puts ""
      
    else                  # assignment with evaluation or ordinary expression      
      if command =~ /^\$([0-9A-Za-z_]+) *= *(.+)$/ then
        variable_name = $1
        expression = $2
      else
        variable_name = nil
        expression = command
      end

      begin
        # look up variables in expression
        subbed_expression = memory.substitute_variables(expression)
        
        # get results
        result = do_calculation(subbed_expression)
        
        # store results to memory
        memory.update_last(result)
        new_variable_name = memory.store(variable_name, result)
        puts "  $#{new_variable_name} = #{result}"
        puts ""
      rescue StandardError => msg
        STDERR.puts "  #{msg}. (Lost? Type \"quit\" or ^C to quit.)"
        puts ""
      end

  end  
end

# Targets for autocomplete. Separate with newlines. Still need to work out
# entries with multiple words. Comments on their own line are allowed.
__END__
# Commonly Used Words #
quit
restore
load
list
ls
save
help
delete
clear
half
quarter
cubic
square
in
per
