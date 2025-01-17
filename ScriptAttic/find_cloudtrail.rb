#!/usr/bin/ruby

# Find shit in your cloudtrail bucket
# 

require 'yaml'
require 'json'
require 'zlib'

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
	opts.on("-d", "--dry-run", "Do everything up to the update/create_stack") do |v|
		Options[:dryrun] = v
	end
	
	opts.on("--date date", "Search date (YYYY-MM-DD") do |date|
		Options[:date] = date
	end

	opts.on("--region r", "Search for events in this region") do |r|
		Options[:search_region] = r
	end

end.parse!

# Based on the date specified, build out the bucket info needed
# This returns a hash with the bucket_name, prefix and region where the bucket lives
def get_path(date)

	cloudtrail_client = Aws::CloudTrail::Client.new()

	# Expect date in YYYY-MM-DD format
	date.gsub!('-', '/')

	# Get the details on there to look from the cloud trail
	resp = cloudtrail_client.describe_trails(include_shadow_trails: true)
	bucket = resp.trail_list[0].s3_bucket_name
	prefix = resp.trail_list[0].s3_key_prefix
	# region = resp.trail_list[0].home_region
	account = resp.trail_list[0].trail_arn.split(':')[4]

# /dcmi-cloudtrail/AWSLogs/759447159602/CloudTrail/ap-southeast-2/2015/10/21/759447159602_CloudTrail_ap-southeast-2_20151021T0300Z_e6J8uz6AyzvPhS0c.json.gz
	# get_object() does not want a preceeding / here. 
	path = "AWSLogs/#{account}/CloudTrail/#{Options[:search_region]}/#{date}"
	if prefix
		path =  prefix + "/" + path
	end

	# Figure out the region where the bucket lives. 
	# S3 client will need to connect to this later
	s3_client = Aws::S3::Client.new()
	resp = s3_client.get_bucket_location({
			bucket: bucket, # required
			use_accelerate_endpoint: false,
			})
	bucket_region = resp.location_constraint
	
	puts "Using Objects in path: s3://#{bucket}/#{path}" if Options[:verbose]
	result = {
		bucket: bucket,
		prefix: path,
		region: bucket_region
	}
	return result
end

# This will iterate over a bucket & prefix and return an array of all the keys in the bucket.
# This might be bad if there are millions of objects
def get_object_list(s3_client, object_info)
	object_list = []

	params = {
		bucket: object_info[:bucket], # required
		prefix: object_info[:prefix],
		max_keys: 1000,
	}

	more = true # will go false when there are no more results
	while more do
		puts params.inspect if Options[:verbose]

		resp = s3_client.list_objects_v2(params)
		puts "Got #{resp.contents.length} objects".yellow

		resp.contents.each do |o|
			object_list.push(o.key)
		end

		more = resp.is_truncated
		if resp.is_truncated 
			params[:continuation_token] = resp.next_continuation_token
		end

	end

	return object_list
end


# Now the fun part, Get each object, parse it, and spit out the key bits from it's 
# little json heart
def process_objects(s3_client, objects, object_info)

	objects.each do |key|
		resp = s3_client.get_object(bucket: object_info[:bucket], key: key)

		json_blob = JSON.parse(Zlib::GzipReader.new(resp.body).read)
		# pp json_blob.inspect  if Options[:jsongoop]

		json_blob['Records'].each do |r|
			service = r['eventSource'].split('.')[0] # takes ec2.amazonaws.com and makes it just ec2

			who = "I-Dont-Know"
			if r['userIdentity']['type'] == "IAMUser"
				who = r['userIdentity']['userName']
			elsif r['userIdentity']['type'] == "AssumedRole"
				who = r['userIdentity']['principalId']
			else
				who = r['userIdentity']['type']
			end
			puts "#{r['eventTime']} #{r['awsRegion']} #{service}:#{r['eventName']} #{who}"
		end
	end
end



def main()
	# Get the details on where cloud trail is putting things
	object_info = get_path(Options[:date])

	# establish a reusable client
	s3_client = Aws::S3::Client.new(region: object_info[:region])

	# Get a list of all the json files in the time period
	objects = get_object_list(s3_client, object_info)
	puts "Got a total of #{objects.length} objects."

	# get the object and parse it, and spit out useful data
	process_objects(s3_client, objects, object_info)

end

# do something
main()

