#!/usr/bin/ruby

# This script is useful if you're on the road and need to permit yourself access to your instance

require 'aws-sdk-resources'
require 'optparse'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options] <name_of_instance>"

  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    options[:verbose] = v
  end
  # opts.on("-r", "--revoke", "revoke my access") do |r|
  #   options[:revoke] = r
  # end
  # opts.on("-i", "--ip ip", "use this IP instead") do |ip|
  #   options[:ip] = ip
  # end
  # opts.on("-p", "--port port", "use this port instead of 22") do |port|
  #   options[:port] = port
  # end
  # opts.on("-R", "--revoke-all", "Revoke All SSH Access") do |all|
  #   options[:revokeall] = all
  # end

end.parse!

# p options
# p ARGV



if ENV['AWS_SECRET_ACCESS_KEY'] == ""
	puts "Your Keys are not in the environment. Failing to do anything"
	exit
end


instance_name=ARGV[0]


ec2=Aws::EC2::Client.new()

begin
	result=ec2.describe_instances({filters: [ { name: "tag:Name", values: [ "#{instance_name}" ] }, { name: "instance-state-name", values: ['running']} ] } )
	# puts result.reservations.inspect
	if result.reservations.length == 0
		puts "Could not find #{instance_name}"
		exit 1
	end
rescue Aws::EC2::Errors::AuthFailure => e
	puts "Auth Failure: #{e.message}. Are you keys loaded?"
	exit 1
end

puts "#{instance_name} uses key #{result.reservations[0].instances[0]['key_name']}"

