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
	opts.on("-d", "--dry-run", "Do everything up to the update/create_stack") do |v|
		Options[:dryrun] = v
	end
	
	opts.on("--user user", "Create Access Key for this user") do |user|
		Options[:user] = user
	end

	opts.on("--key key", "Deactivate/Delete this key") do |key|
		Options[:key] = key
	end

	opts.on("--delete", "Delete key specificed by --key") do |d|
		Options[:delete] = d
	end

	# opts.on("--deactivate", "Deactivate key specified by --key") do |d|
	# 	Options[:deactivate] = d
	# end

end.parse!

if ! Options[:user] ; then
	puts "--user is required"
	exit 1
end


def list_access_keys()
	iam_client = Aws::IAM::Client.new()
	begin
		resp = iam_client.list_access_keys({
			user_name: Options[:user],
		})
		puts "Access keys for #{Options[:user]}: "
		resp.access_key_metadata.each do |k|
			puts "\t#{k.access_key_id} is #{k.status} (created: #{k.create_date})"
		end
	rescue Aws::IAM::Errors::NoSuchEntity => e
		puts "User #{Options[:user]} does not exist. Aborting..."
		exit 1
	rescue Aws::IAM::Errors::ServiceError => e
		puts "Other error: #{e.message}. Aborting...."
		exit 1	
	end
end


iam_client = Aws::IAM::Client.new()

# We need to make sure the user exists, and the path indicates they are a service account. 
begin
	resp = iam_client.get_user({
	  user_name: Options[:user]
	})

	user = resp.user
	if user.path != "/srv/" ; then
		puts "#{user.user_name} is not a service user. Path is #{user.path}"
		# exit 1
	end
rescue Aws::IAM::Errors::NoSuchEntity => e
	puts "User #{Options[:user]} does not exist. Aborting..."
	exit 1
rescue Aws::IAM::Errors::ServiceError => e
	puts "Other error: #{e.message}. Aborting...."
	exit 1	
end

# We also should make sure they don't have a login_profile (ie password) set
begin
	resp = iam_client.get_login_profile({
	  user_name: Options[:user]
	})

	if resp.login_profile ; then
		puts "#{Options[:user]} has a login profile (ie password) aborting...."
		exit 1
	end
rescue Aws::IAM::Errors::NoSuchEntity => e
	puts "No login profile. Proceeding" if Options[:verbose]
rescue Aws::IAM::Errors::ServiceError => e
	puts "Other error: #{e.message}. Aborting...."
	exit 1
end


# We may have to delete a key before we can create a new one.
if Options[:delete] ; then
	begin
		resp = iam_client.get_access_key_last_used({
			access_key_id: Options[:key], # required
		})
		if resp.user_name != Options[:user]
			puts "AccessKey #{Options[:key]} belongs to #{resp.user_name} not #{Options[:user]}. Aborting..."
			exit 1
		end

		puts "Access Key Last used on #{resp.access_key_last_used.last_used_date} for #{resp.access_key_last_used.service_name}"
		puts "Shall I proceed? (type the access key again to confirm)"
		answer = gets
		answer.chomp!()
		if answer != Options[:key] ; then
			puts "Ok. Aborting now"
			exit 
		end
		# OMG here we go....
	rescue Aws::IAM::Errors::NoSuchEntity => e
		puts "Unable to find information about #{Options[:key]}. Aborting..."
		exit 1
	rescue Aws::IAM::Errors::ServiceError => e
		puts "Other error: #{e.message}. Aborting...."
		exit 1
	end

	# Now we do the deletion.
	begin
		resp = iam_client.delete_access_key({
			user_name: Options[:user],
			access_key_id: Options[:key], # required
		})
	rescue Aws::IAM::Errors::ServiceError => e
		puts "Unable to delete key: #{e.message}. Aborting...."
		exit 1
	end

end # Delete Key

# Now create the key
begin
	resp = iam_client.create_access_key({
	  user_name: Options[:user]
	})

	puts "UserName:  #{resp.access_key.user_name}"
	puts "AccessKey: #{resp.access_key.access_key_id}"
	puts "SecretKey: #{resp.access_key.secret_access_key}"
	puts "Status:    #{resp.access_key.status}"
	puts "Creation:  #{resp.access_key.create_date}"
	exit 0
rescue Aws::IAM::Errors::LimitExceeded => e
	puts "Too many API keys in use. #{e.message}"
	list_access_keys()
	exit 1
rescue Aws::IAM::Errors::ServiceError => e
	puts "Other error: #{e.message}. Aborting...."
	exit 1
end