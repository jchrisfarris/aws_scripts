#!/usr/bin/ruby

# This script is useful if you're on the road and need to permit yourself access to your instance

require 'aws-sdk-resources'
require 'optparse'
require 'json'
require 'pp'

Options = {}
Options[:days] = 1 # Default
OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options] <name_of_instance>"

  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    Options[:verbose] = v
  end
  opts.on("-t", "--timestamps", "include timestamps") do |v|
    Options[:timestamps] = v
  end
  opts.on("-d", "--days days", "Go back $days days in the search") do |days|
    Options[:days] = days
  end
  opts.on("-g", "--log-group group", "Name of the Log Group for CloudTrail") do |group|
    Options[:group] = group
  end

end.parse!


if ENV['AWS_SECRET_ACCESS_KEY'] == ""
	puts "Your Keys are not in the environment. Failing to do anything"
	exit
end

Log_client = Aws::CloudWatchLogs::Client.new()

def get_streams()
	stream_list = []
	begin
		resp = Log_client.describe_log_streams({
			log_group_name: Options[:group], # required
			order_by: "LastEventTime", # accepts LogStreamName, LastEventTime
			descending: true,
		})
		resp.log_streams.each do |s|
			stream_list.push(s['log_stream_name'])
		end
	rescue Aws::CloudWatchLogs::Errors::ResourceNotFoundException => e
		puts "Cannot find log-group: #{Options[:group]}"
		exit 1
	end
	return stream_list
end # get_stream()

def get_events(stream_name)
	event_list = []
	begin 
		resp = Log_client.filter_log_events({
		  log_group_name: Options[:group], # required
		  # log_stream_names: [stream_name],
		  start_time: (Time.now().to_i - (Options[:days].to_i * 86400)) * 1000,
		  filter_pattern: '{ ($.errorCode = "AccessDenied*") }',
		  interleaved: true,
		})

		# Decode the JSON Text that is message, and write it back into the hash 
		resp.events.each do |e|
			event_list.push(JSON.parse(e.message))
		end
		return(event_list)

	rescue Aws::CloudWatchLogs::Errors::ResourceNotFoundException => e
		puts "Invalid Log Group"
		exit 1

	rescue Aws::CloudWatchLogs::Errors::AuthFailure => e
		puts "Auth Failure: #{e.message}. Are you keys loaded?"
		exit 1
	end
end # get_events()

def display_event(event)

	if Options[:timestamps]
		# puts "#{event['eventTime']} in #{event['awsRegion']} #{event['errorMessage']}"
		puts "#{event['eventTime']} #{event['errorMessage']}"
	else
		puts event['errorMessage']
	end
end # display_event()

def dedup_events(event_list)
	messages = []
	event_list.each do |e|
		messages.push(e['errorMessage'])
	end
	return messages.uniq.sort
end # dedup_events

events = []
streams = get_streams()
streams.each do |s|
  events.concat(get_events(s))
end
events.sort_by! { |k| k['eventTime'] }

# events = get_events("foo")

messages = dedup_events(events)
events.each do |e|
	display_event(e)
end
puts "got #{events.length()} events of which #{messages.length()} are unique"
