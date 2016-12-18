#!/usr/bin/ruby

require 'yaml'
require 'json'
require 'zlib'

require 'optparse'
require 'colorize'
require 'pp'

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

	opts.on("-h", "human readable") do |h|
		Options[:human] = h
	end

	opts.on("-t", "Show Totals only") do |t|
		Options[:total] = t
	end
	
	opts.on("--bucket bucket", "report on specific bucket") do |bucket|
		Options[:bucket] = bucket
	end

	opts.on("--keyword key", "Report only on buckets containing keyword") do |key|
		Options[:keyword] = key
	end

	opts.on("--type type", "Report only on storage type. Valid Types are: StandardStorage StandardIAStorage ReducedRedundancyStorage") do |type|
		Options[:type] = type
	end

	opts.on("--objects", "Get Count of object instead of size") do |o|
		Options[:objects] = o
	end

	# opts.on("--deactivate", "Deactivate key specified by --key") do |d|
	# 	Options[:deactivate] = d
	# end

end.parse!

# if ! Options[:user] ; then
# 	puts "--user is required"
# 	exit 1
# end

StorageTypes=["StandardStorage","StandardIAStorage","ReducedRedundancyStorage"]
S3_client = Aws::S3::Client.new()


def get_bucket_storage_size(bucket_name)

	bucket_region = get_bucket_region(bucket_name)
	cloudwatch_client = Aws::CloudWatch::Client.new(
		region: bucket_region
	)

	begin

		total_size = 0
		StorageTypes.each do |type| 
			next if Options[:type] && ! type.include?(Options[:type])
			resp = cloudwatch_client.get_metric_statistics({
				namespace: "AWS/S3", # required
				metric_name: "BucketSizeBytes", # required
				dimensions: [
					{
						name: "BucketName", # required
						value: bucket_name
					},
					{
						name: "StorageType", # required
						value: type, # required
					},
				],
				start_time: Time.now-(86400*2), # required
				end_time: Time.now, # required
				period: 86400, # required
				statistics: ["Maximum"], # required, accepts SampleCount, Average, Sum, Minimum, Maximum
			})

			if resp.datapoints.length != 0 
				if Options[:human]
					size = resp.datapoints[0].maximum.to_i.to_filesize
					puts "#{size.to_s.ljust(12, " ")} #{bucket_name} (#{type})" if ! Options[:total]
				else
					puts "#{resp.datapoints[0].maximum.to_i}\t\t #{bucket_name} (#{type})" if ! Options[:total]
				end
				total_size = total_size + resp.datapoints[0].maximum.to_i
			end
		end
		if Options[:human]
			size = total_size.to_i.to_filesize
			puts "#{size.to_s.ljust(12, " ")} #{bucket_name} (TOTAL)"
		else
			puts "#{total_size}\t\t #{bucket_name} (TOTAL)"
		end
		return(total_size)
	rescue Aws::CloudWatch::Errors::InvalidParameterCombination => e
		puts "Error: #{e.message}".red
	end
end # process_bucket

def get_bucket_object_count(bucket_name)

	bucket_region = get_bucket_region(bucket_name)

	cloudwatch_client = Aws::CloudWatch::Client.new(
		region: bucket_region
	)

	begin
		resp = cloudwatch_client.get_metric_statistics({
			namespace: "AWS/S3", # required
			metric_name: "NumberOfObjects", # required
			dimensions: [
				{
					name: "BucketName", # required
					value: bucket_name
				},
				{
					name: "StorageType", # required
					value: "AllStorageTypes", # required
				},
			],
			start_time: Time.now-(86400*2), # required
			end_time: Time.now, # required
			period: 86400, # required
			statistics: ["Maximum"], # required, accepts SampleCount, Average, Sum, Minimum, Maximum
		})

		if resp.datapoints.length != 0 
			obj_count = resp.datapoints[0].maximum.to_i
			if Options[:human]
				count = obj_count.to_s.reverse.gsub(/(\d{3})/,"\\1,").chomp(",").reverse
			else
				count = obj_count
			end
			puts "#{bucket_name} has #{count} objects"
		end
	rescue Aws::CloudWatch::Errors::InvalidParameterCombination => e
		puts "Error: #{e.message}".red
	end
end # get_bucket_object_count

def main()
	grand_total = 0

	# Start with a list of buckets
	bucket_resp = S3_client.list_buckets()
	bucket_resp.buckets.each do |b|

		next if Options[:keyword] && ! b.name.include?(Options[:keyword])
		if Options[:objects]
			get_bucket_object_count(b.name)
		else
			bucket_size = get_bucket_storage_size(b.name)
			grand_total = grand_total + bucket_size
		end
	end

	if ! Options[:objects]
		if Options[:human]
			size = grand_total.to_i.to_filesize
		else
			size = grand_total
		end
		puts "Total across all buckets: #{size}".green
	end
end

class String
  def fix(size, padstr=' ')
    self[0...size].rjust(size, padstr) #or ljust
  end
end

class Integer
  def to_filesize
    {
      'B'  => 1024,
      'KB' => 1024 * 1024,
      'MB' => 1024 * 1024 * 1024,
      'GB' => 1024 * 1024 * 1024 * 1024,
      'TB' => 1024 * 1024 * 1024 * 1024 * 1024
    }.each_pair { |e, s| return "#{(self.to_f / (s / 1024)).round(2)}#{e}" if self < s }
  end
end

def get_bucket_region(bucket_name)
	begin
		location_resp = S3_client.get_bucket_location(bucket: bucket_name)
	rescue Aws::S3::Errors::AccessDenied => e
		puts "Access Denied for bucket #{bucket_name}".red
		exit 1
	end

	bucket_region = "us-east-1"
	if location_resp.location_constraint != ""
		bucket_region = location_resp.location_constraint
	end

	# # puts location_resp.inspect
	puts "#{bucket_name} in #{bucket_region}".green if Options[:verbose]
	return(bucket_region)
end

begin
	if Options[:bucket]
		if Options[:objects]
			get_bucket_object_count(Options[:bucket])
		else
			get_bucket_storage_size(Options[:bucket])
		end		
	else
		main()
	end
rescue Interrupt => e 
	puts "aborting".red
	exit 1
end