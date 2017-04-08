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
  opts.on("-b", "--bucket name", "bucket name") do |bucket|
    options[:bucket] = bucket
  end

   opts.on("-d", "--delete", "Delete the parts") do |v|
    options[:delete] = v
  end 

 opts.on("-s", "--size", "Calc and Show size of parts") do |v|
    options[:size] = v
  end 

end.parse!


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

if ENV['AWS_SECRET_ACCESS_KEY'] == ""
	puts "Your Keys are not in the environment. Failing to do anything"
	exit
end

total_size = 0

s3client = Aws::S3::Client.new()
begin 

	bucket_list = []
	if options[:bucket].nil?
		resp1 = s3client.list_buckets()
		bucket_list = resp1.buckets 
	else
		bucket_list[0]['name'] = options[:bucket]
	end

	puts "Looking for multipart uploads across #{bucket_list.length} buckets" if options[:verbose]

	bucket_list.each do |b|
		bucket = b['name']
		resp = s3client.get_bucket_location({
			bucket: bucket
		})

		# This is lovely, us-east-1 buckets don't return a value here. 
		if resp.location_constraint == ""
			location = "us-east-1"
		else
			location = resp.location_constraint
		end

		puts "#{bucket} is in #{location}" if options[:verbose]

		client = Aws::S3::Client.new({
			region: location
		})

		resp = client.list_multipart_uploads({
		  bucket: bucket, # required
		})
		resp.uploads.each do |u|
			object_size = ""
			if options[:size]
				object_size = 0
				resp = client.list_parts({
					bucket: bucket, # required
					key: u.key, # required
					upload_id: u.upload_id, # required
				})
				resp.parts.each do |p|
					object_size = object_size + p.size
					total_size = total_size + p.size
				end
			end

			puts "#{bucket} #{u.key} #{u.initiated} #{object_size.to_filesize}"

			if options[:delete]
				resp = client.abort_multipart_upload({
					bucket: bucket, # required
					key: u.key, # required
					upload_id: u.upload_id, # required
				})
			end
		end
	end

rescue Aws::S3::Errors::ServiceError => e
	puts "Failure: " + e.message
end 

if options[:size]
	puts "Total Size: #{total_size.to_filesize}"
end
