#!/usr/bin/ruby

require 'yaml'
require 'json'
require 'optparse'
require 'ostruct'
require 'fileutils'

#quit unless our script gets two command line arguments
# unless ARGV.length == 3
#   puts "Dude, not the right number of arguments."
#   puts "Usage: ruby YJ_Convert.rb [-j][-y] json_file.json yaml_file.yaml\n"
#   exit
# end

$input_file = ARGV[1]

if ! File.exists?($input_file)
  puts "unable to find or open #{$input_file}"
  exit 1
end

options = OpenStruct.new
OptionParser.new do |opt|
  opt.on('-j', '--json', 'Convert to JSON') { |o| options.json = o }
  opt.on('-y', '--yaml', 'Convert to YAML') { |o| options.yaml = o }
end.parse!

case
  when options.yaml == true
    puts(YAML.dump(JSON.parse(IO.read($input_file))))
  when options.json == true
    j_file = YAML.load_file(File.open("#{$input_file}", 'r'))
    puts JSON.pretty_generate(j_file)
end
