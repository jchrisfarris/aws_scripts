#!/usr/bin/ruby

require 'yaml'
require 'json'
require 'aws-sdk-resources'
require 'optparse'
require 'colorize'
require 'pp'

# Option Processing
Options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: add_user.rb [options]"

  opts.on("-v", "--verbose", "Run verbosely") do |v|
    Options[:verbose] = v
  end


  opts.on("-u", "--username username", "Username to create") do |username|
    Options[:username] = username
  end
  opts.on("-p", "--path path", "path to place the user in") do |path|
    Options[:path] = path
  end

  opts.on("-P", "--password pass", "Set the users password to this. Otherwise a randon 10char string will be used.") do |password|
    Options[:password] = password
  end  
  opts.on("-g", "--group group", "Place the new user in this Group") do |group|
    Options[:group] = group
  end

  opts.on("--delete", "Delete the user, don't create it") do |v|
    Options[:delete] = v
  end

  opts.on("--reset", "reset the user's password") do |v|
    Options[:reset] = v
  end

  opts.on("--delete-mfa", "delete/reset the user's MFA") do |v|
    Options[:delete_mfa] = v
  end

end.parse!


# Grab some goop for a password
def make_up_password
	o = [('a'..'z'), ('A'..'Z'), ('0'..'9')].map { |i| i.to_a }.flatten
	pass = (0...12).map { o[rand(o.length)] }.join + "@"
	puts "Using #{pass} for password\n"
	return pass
end

# Delete a user
# Which requires:
# 	deleting their login profile
# 	deleting them from all groups
# 	removing any API Keys
# all before the user can be deleted. 
def delete_user(iam_client)


	# Remove Login Profile
	begin
		iam_client.delete_login_profile({
			user_name: Options[:username],
		})
	rescue Exception => e
		puts "Login profile already gone"
	end

	# Remove Access Keys
	begin
		resp = iam_client.list_access_keys({
			user_name: Options[:username]
		})
		resp.access_key_metadata.each do |k|
			resp = iam_client.delete_access_key({
				user_name: Options[:username], # required
				access_key_id: k.access_key_id # required
			})
		end
	rescue Exception => e
		puts "issue removing access keys: #{e.message}"
	end			

	# Remove MFA
	begin 
		resp = iam_client.list_mfa_devices({
			user_name: Options[:username]
		})

		# First deactivate then remove. I don't think you can have multiple MFA, but the structure says you can
		resp.mfa_devices.each do |d|
			iam_client.deactivate_mfa_device({
				user_name: Options[:username], # required
				serial_number: d.serial_number, # required
			})
			iam_client.delete_virtual_mfa_device({
				serial_number: d.serial_number, # required
			})
		end
	rescue Exception => e
		puts "issue removing MFA Devices: #{e.message}"
	end

	# Remove managed policies
	begin 
		resp = iam_client.list_attached_user_policies({
			user_name: Options[:username]
		})
		resp.attached_policies.each do |p|
			iam_client.detach_user_policy({
				user_name: Options[:username], # required
				policy_arn: p.policy_arn, # required
			})
		end
	rescue Exception => e
		puts "issue removing inline policies: #{e.message}"
	end

	# Remove inline policies
	begin 
		resp = iam_client.list_user_policies({
			user_name: Options[:username]
		})
		resp.policy_names.each do |p|
			iam_client.delete_user_policy({
				user_name: Options[:username], # required
				policy_name: p, # required
			})
		end
	rescue Exception => e
		puts "issue removing inline policies: #{e.message}"
	end

	# Remove from Groups
	begin 
		resp = iam_client.list_groups_for_user({
			user_name: Options[:username]
		})
		resp.groups.each do |g|
			iam_client.remove_user_from_group({
				group_name: g.group_name, # required
				user_name: Options[:username], # required
			})
		end
	rescue Exception => e
		puts "issue removing from groups: #{e.message}"
	end

	# Purge CodeCommit SSH Keys
	begin
		resp = iam_client.list_ssh_public_keys({
			user_name: Options[:username],
		})
		resp.ssh_public_keys.each do |key|
			resp = iam_client.delete_ssh_public_key({
				user_name: Options[:username], # required
				ssh_public_key_id: key.ssh_public_key_id, # required
			})
		end
	rescue Exception => e
		puts "Issue removing SSH Keys #{e.message}"
	end

	# yay. Can finally do what I came for.
	begin
		iam_client.delete_user({
			user_name: Options[:username],
		})
		exit 0
	rescue Aws::IAM::Errors::DeleteConflict => e
		puts "Other error deleting user: #{e.message}"
		exit 1
	rescue Aws::IAM::Errors::NoSuchEntity =>e 
		puts "No such user #{Options[:username]} to delete."
		exit 1
	end
end


# Reset User's MFA
# Which requires:
# 	Deactivate the MFA
#   Delete the MFA
def delete_mfa(iam_client)

	# Remove MFA
	begin 
		resp = iam_client.list_mfa_devices({
			user_name: Options[:username]
		})

		# First deactivate then remove. I don't think you can have multiple MFA, but the structure says you can
		resp.mfa_devices.each do |d|
			iam_client.deactivate_mfa_device({
				user_name: Options[:username], # required
				serial_number: d.serial_number, # required
			})
			iam_client.delete_virtual_mfa_device({
				serial_number: d.serial_number, # required
			})
		end
		exit 0
	rescue Exception => e
		puts "issue removing MFA Devices: #{e.message}"
		exit 1
	end
end


# Add a user
# Which entails
# 	creating the IAM user
# 	Giving them a login-profile (ie a password)
# 	making sure they change it on first login
# 	Adding them to a group so they can do something useful
def add_user(iam_client)

	# Catch any exceptions. We don't clean up if we do.
	begin
		# create the user
		resp = iam_client.create_user({
			path: Options[:path],
			user_name: Options[:username],
		})
		user = resp.user
		pp user if Options[:verbose]

		# Now add a login Profile
		resp = iam_client.create_login_profile({
			user_name: Options[:username], # required
			password: Options[:password], # required
			password_reset_required: true,
		})
		profile = resp.login_profile
		pp profile if Options[:verbose]

		resp = iam_client.add_user_to_group({
		  group_name: Options[:group], # required
		  user_name: Options[:username], # required
		})

		pp resp if Options[:verbose]

		# This gets the account alias which is part of the login url
		resp = iam_client.list_account_aliases()
		pp resp if Options[:verbose]
		account_alias = resp.account_aliases[0]
	rescue Exception => e
		puts "Error creating account #{e.message}"
		exit 1
	end

	puts "User: #{Options[:username]} (#{user.arn}) created and added to #{Options[:group]}"
	puts "Login url: https://#{account_alias}.signin.aws.amazon.com/console"
	puts "Username: #{Options[:username]}"
	puts "You must change your password and set MFA on first login by going to this URL after setting your new password:"
	puts "https://console.aws.amazon.com/iam/home?region=us-east-1#/users/#{Options[:username]}?section=security_credentials"
	puts "---end of email ---\n\n"
	puts "Password: #{Options[:password]}"

end

# Reset a user's password
def reset_password(iam_client)

	# Catch any exceptions. We don't clean up if we do.
	begin

		# Now add a login Profile
		resp = iam_client.update_login_profile({
			user_name: Options[:username], # required
			password: Options[:password], # required
			password_reset_required: true,
		})
		# profile = resp.login_profile
		# pp profile if Options[:verbose]

		# This gets the account alias which is part of the login url
		resp = iam_client.list_account_aliases()
		pp resp if Options[:verbose]
		account_alias = resp.account_aliases[0]
	rescue Exception => e
		puts "Error creating account #{e.message}"
		exit 1
	end

	puts "Password for #{Options[:username]} reset to #{Options[:password]}\n\n"
	puts "Login url: https://#{account_alias}.signin.aws.amazon.com/console"
	puts "Username: #{Options[:username]}"
	puts "Password: #{Options[:password]}"
	puts "You must change your password and set MFA on first login by going to this URL after setting your new password:"
	puts "https://console.aws.amazon.com/iam/home?region=us-east-1#/users/#{Options[:username]}?section=security_credentials"
	exit 0
end

# These are required
if ! Options[:username] 
	puts "No username specified with --username"
	exit 1
end

# Defaults
Options[:path] = "/" if ! Options[:path]
iam_client = Aws::IAM::Client.new()

delete_user(iam_client) if Options[:delete]
delete_mfa(iam_client) if Options[:delete_mfa]

Options[:password] = make_up_password() if ! Options[:password]

reset_password(iam_client) if Options[:reset]

if ! Options[:group] 
	puts "No group"
	exit 1
end


begin
	add_user(iam_client)
rescue Aws::IAM::Errors::EntityAlreadyExists => e
	puts "User already Exists."
	exit 1
end













