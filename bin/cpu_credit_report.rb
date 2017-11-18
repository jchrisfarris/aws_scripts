#!/usr/bin/ruby

# Reports on the CPU Credits of your t2 instances. 
# https://aws.amazon.com/ec2/instance-types/#burst

require 'aws-sdk-resources'
require 'optparse'
require 'colorize'


options = {}
options[:threshold] = 10.0
OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options] <name_of_instance>"

  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    options[:verbose] = v
  end
  opts.on("--no-color", "No Color (helpful if grepping)") do |r|
    options[:nocolor] = r
  end
  opts.on("-t", "--threshold float", "Alert at this threshold") do |float|
    options[:threshold] = float
  end
  opts.on("-a", "--all", "Show all Credits, not just below threshold") do |v|
    options[:all] = v
  end


end.parse!

# Convert Instance tags to a hash
def tags_to_hash(key_values)
	output = {}
	key_values.each do |pair|
		output[pair['key']] = pair['value']
	end
	return output
end
# end tags_to_hash()

cloudwatch = Aws::CloudWatch::Client.new()
ec2=Aws::EC2::Client.new()

begin
	result=ec2.describe_instances({filters: [ 
		{ name: "instance-type", values: [ "t2.nano", "t2.micro","t2.small","t2.large","t2.xlarge"] }, 
		{ name: "instance-state-name", values: ['running']} ] } )
	# puts result.reservations.inspect
	if result.reservations.length == 0
		puts "Could not find any t2 instances"
		exit 1
	end
rescue Aws::EC2::Errors::RequestExpired => e
	puts "Auth Failure: #{e.message}."
	exit 1
rescue Aws::EC2::Errors::AuthFailure => e
	puts "Auth Failure: #{e.message}. Are you keys loaded?"
	exit 1
end

result.reservations.each do |reservation|
	reservation.instances.each do |i|
		cw_response = cloudwatch.get_metric_statistics({
		  namespace: "AWS/EC2", # required
		  metric_name: "CPUCreditBalance", # required
		  dimensions: [
		    {
		      name: "InstanceId", # required
		      value: i.instance_id, # required
		    },
		  ],
		  start_time: Time.now.getutc - 20*60, # required
		  end_time: Time.now, # required
		  period: 300, # required
		  statistics: ["Minimum"], # accepts SampleCount, Average, Sum, Minimum, Maximum
		})

		tags = tags_to_hash(i.tags)
		message = "#{i.instance_id} (#{tags['Name']}) Credit: #{cw_response.datapoints[0].minimum}"
		if options[:nocolor]
			puts message
		else
			if cw_response.datapoints[0].minimum <= options[:threshold].to_f
				puts message.red 
			else
				puts message.green if options[:all]
			end
		end
	end
end