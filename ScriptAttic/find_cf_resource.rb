#!/usr/bin/ruby

# Find which Stack the specified Resource is in
# 

require 'yaml'
require 'json'

require 'optparse'
require 'colorize'
require 'pp'

# this version of the SDK supports changesets
gem 'aws-sdk-resources', '>= 2.4.4'
require 'aws-sdk-resources'



# # Option Processing
# -D --debug: Dump lots of puts something.inspect
# -t --test: Validate your template
# -g --generate: generate a manifest file from a template
# -p --stack-policy: Specify a new Stack policy for an update. 

Options = {}
OptionParser.new do |opts|
	opts.banner = "Usage: deploy.rb [options]"

	opts.on("-v", "--verbose", "Run verbosely") do |v|
		Options[:verbose] = v
	end

	opts.on("-r", "--resource resource_id", "Find This Resource ID in all the stacks") do |resource_id|
		Options[:resource_id] = resource_id
	end
	
end.parse!


# return the stack specified by stack_name
# Will barf if there are multiple stacks with the same name
def get_stack(stack_id, cf_client)
	# Does this stack exist in my region? 
	begin 
		resp = cf_client.describe_stacks({ stack_name: stack_id})
		# Make sure resp.stacks[] has only 1 
		if resp.stacks.length > 1
			puts "ERROR: Multiple Stacks with name #{stack_id} exist".red
			exit 1
		else
			# puts resp.stacks[0].inspect
			return resp.stacks[0]
		end
	rescue Aws::CloudFormation::Errors::ValidationError => e
		return nil
	rescue Aws::CloudFormation::Errors::ServiceError => e
		puts "ERROR: Unknown error #{e.message}. Cannot Continue. Exiting".red
		exit 1
	end
end


def get_stack_status(stack_id, cf_client)
	stack = get_stack(stack_id, cf_client)
	return "#{stack.stack_status} @ #{stack.last_updated_time}"
end


# Key look, there is one API call to do what we want. 
def find_resource(cf_client, physical_resource_id)

	next_token = "0"
	begin
		resp = cf_client.describe_stack_resources({
			physical_resource_id: physical_resource_id 
			})
		puts "Got #{resp.stack_resources.length} resources".yellow if Options[:verbose]
		resp.stack_resources.each do |r|
			if physical_resource_id == r.physical_resource_id
				return(r)
			end
		end
		return false
	rescue Exception => e
		puts "Error finding physical_resource_id: #{e.message}"
	end
end


cf_client = Aws::CloudFormation::Client.new(region: ENV['AWS_DEFAULT_REGION'], profile: ENV['AWS_DEFAULT_PROFILE'])
resource = find_resource(cf_client, Options[:resource_id])
if ! resource 
	puts "Unable to file Resource called #{Options[:resource_id]}"
else
	puts "Found Resource #{resource.physical_resource_id}"
	puts "\tStackName: #{resource.stack_name}"
	puts "\tStack ID: #{resource.stack_id}"
	puts "\tLogical ID: #{resource.logical_resource_id}"
	puts "\tResource Type: #{resource.resource_type}"
	puts "\tResource Status: #{resource.resource_status}"
	puts "\tStack Status: #{get_stack_status(resource.stack_id, cf_client)}"
end




