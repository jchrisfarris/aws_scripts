#!/usr/bin/ruby

# Script to calculate the size and therefore the cost of your S3 storage. 
# Assumes IAM role or API Keys in the shell environment

require 'aws-sdk-resources'

# uncomment this for troubleshooting
#AWS.config(:http_wire_trace => true)

s3 = Aws::S3::Resource.new()

@delimiter = "\t"

bucket_name = ARGV[0]

if ! bucket_name
  puts "Usage: script <bucketname"
  exit 1
end

# A cool trick would be to get this cost via API
# TODO - add the new infrequent access tier
costs = {  "GLACIER" => 0.01 ,
	         "REDUCED_REDUNDANCY" => 0.024,
	         "STANDARD" => 0.03 }

# Initalize a empty calc table
sizes = { "GLACIER" => 0 ,
	  "REDUCED_REDUNDANCY" => 0,
	  "STANDARD" => 0 }

# And count the objects cause we're iterating through the bucket
obj_count = 0

bucket = s3.bucket(bucket_name)
bucket.object_versions.each do |o|

  obj_count += 1
  storageclass = o.storage_class
  sizes[storageclass] = sizes[storageclass] + o.size 
end

#puts sizes.inspect

total_cost = 0.0
sizes.keys.each do |type|
  bytes = sizes[type].to_f
  gbytes = bytes / 1024 / 1024 / 1024
  cost = gbytes * costs[type]
  puts type + ": $" + cost.round(2).to_s + " for " + gbytes.to_s + " gigabytes of data"
  total_cost += cost
end


puts "Total Objects in " + bucket_name + " : " + obj_count.to_s
puts "Total Cost for " + bucket_name + " : $" + total_cost.round(2).to_s + " per month"
