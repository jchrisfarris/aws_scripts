#!/usr/bin/ruby

# This script takes a Manifest file and deploys the stack.
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
	opts.on("-d", "--dry-run", "Do everything up to the update/create_stack") do |v|
		Options[:dryrun] = v
	end
	opts.on("-m", "--manifest file", "Process this manifest file") do |file|
		Options[:manifest] = file
	end
	opts.on("-D", "--debug file", "Spits out logs of debug info ") do |file|
		Options[:debug] = file
	end
	opts.on("-t", "--test file", "tests the template file") do |file|
		Options[:test] = file
	end
	opts.on("-g", "--generate template", "Generate a template manifest from a cloudformation template ") do |template|
		Options[:generate] = template
	end
	opts.on("-u", "--allow_update resource1,resource2,resourceN", Array, "allow updates to specified resource overriding the stack policy") do |r|
		Options[:allow_update] = r
	end
	opts.on("--price", "Print the cost of the stack and exit") do |v|
		Options[:price] = v
	end
	opts.on("--force", "Force the operation and bypass safety checks") do |v|
		Options[:force] = v
	end
	opts.on("-p", "--update-policy", "Force the update of the stack policy") do |v|
		Options[:update_policy] = v
	end
	opts.on("--post-install command", "Execute the Post Install Script Only!") do |command|
		Options[:postinstall] = command
	end
	opts.on("--pre-install command", "Execute the Pre Install Script Only!") do |command|
		Options[:preinstall] = command
	end
	opts.on("--create-changeset name", "Create and show the changeset") do |name|
		Options[:create_changeset] = name
	end
	opts.on("--create-changeset-description description", "Description for a new changeset") do |description|
		Options[:create_changeset_description] = description
	end
	opts.on("--execute-changeset name", "Execute Previously Created changeset") do |name|
		Options[:execute_changeset] = name
	end
	opts.on("--delete-changeset name", "Delete a Previously Created changeset") do |name|
		Options[:delete_changeset] = name
	end
	opts.on("--describe-changeset name", "Show Previously Created changeset") do |name|
		Options[:describe_changeset] = name
	end
	opts.on("--list-changesets", "List the names of the changesets for this stack") do |v|
		Options[:list_changesets] = v
	end
	opts.on("--template-url template_url", "Override Manifest to use the following template URL") do |template_url|
		Options[:template_url] = template_url
	end
end.parse!

puts "Override Parameters: " if Options[:verbose]
pp ARGV if Options[:verbose]
# exit 1

# These are defined for both colorization of status, and to determine success/fail.
ResourceGoodStatus=["CREATE_COMPLETE",  "UPDATE_COMPLETE"]
ResourceBadStatus=[ "CREATE_FAILED", "DELETE_IN_PROGRESS", "DELETE_FAILED", "DELETE_COMPLETE",
		"DELETE_COMPLETE", "DELETE_SKIPPED", "UPDATE_FAILED"]
ResourceTempStatus=["CREATE_IN_PROGRESS", "UPDATE_IN_PROGRESS"]
StackTempStatus=["N/A", "CREATE_IN_PROGRESS",  "ROLLBACK_IN_PROGRESS",  "DELETE_IN_PROGRESS", "UPDATE_IN_PROGRESS",
		"UPDATE_COMPLETE_CLEANUP_IN_PROGRESS",  "UPDATE_ROLLBACK_IN_PROGRESS", "UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS"]
StackDoneStatus=["CREATE_FAILED", "CREATE_COMPLETE", "ROLLBACK_FAILED", "ROLLBACK_COMPLETE", "DELETE_FAILED", "DELETE_COMPLETE",
		"UPDATE_COMPLETE",  "UPDATE_ROLLBACK_FAILED",  "UPDATE_ROLLBACK_COMPLETE"]
StackGoodStatus=["CREATE_COMPLETE", "UPDATE_COMPLETE"]



def get_manifest()

	if ! Options[:manifest]
		puts "You didn't specify a manifest file. Not doing anything"
		exit 1
	end

	begin
		manifest = YAML.load_file(Options[:manifest])
	rescue Psych::SyntaxError => e
		puts "Syntax error with Manifest: #{e.message}"
		exit 1
	rescue => e
		puts "Unknown error processing Manifest: #{e.message}"
		exit 1
	end
	DebugLog.write("Manifest: " + manifest.inspect + "\n\n\n") if Options[:debug]

	# Allow override of template_url on commandline
	if Options[:template_url]
		manifest['S3Template'] = Options[:template_url]
	end

	if ! ( manifest['JsonTemplate'] || manifest['LocalTemplate']) && ! manifest['S3Template']
		puts "Your manifest must contain either LocalTemplate, JsonTemplate or S3Template. I cannot proceed."
		exit 1
	end
	if ( manifest['JsonTemplate'] || manifest['LocalTemplate']) && manifest['S3Template']
		puts "Cannot specify both LocalTemplate, JsonTemplate and S3Template in the manifest file. I cannot proceed."
		exit 1
	end
	return(manifest)
end # get_manifest


def get_template(manifest, cf_client)
	# Validate the template and get back the hash of parameters we need to populate
	if manifest['JsonTemplate']
		template_body = File.read(manifest['JsonTemplate'])
		DebugLog.write ("Template Body: #{template_body}") if Options[:debug]
	elsif manifest['LocalTemplate']
		template_body = File.read(manifest['LocalTemplate'])
		DebugLog.write ("Template Body: #{template_body}") if Options[:debug]
	else
		template_body = nil
	end
	return(template_body)
end

def get_deploy_params(manifest, cf_client, template_body)
	# Validate the template body and get back the list of params
	begin
		if manifest['S3Template']
			resp = cf_client.validate_template({template_url: manifest['S3Template']})
		else
			resp = cf_client.validate_template({template_body: template_body})
		end
		stack_params = resp.parameters
		# puts stack_params.inspect
	rescue Exception => e
		puts "ERROR: Unable to validate the template: #{e.message}. Aborting"
		exit 1
	end

	# Get the resources from the prerequisite stacks
	resources = {}
	if manifest['DependsOnStacks'] != nil
		manifest['DependsOnStacks'].each do |stack|
			resources[stack] = get_stack_resources(stack, cf_client)
		end
	end

	# Here we merge it all into a master params hash
	deploy_params = populate_parameters(manifest, stack_params, resources)
	# puts "\n\n" + deploy_params.inspect

	return(deploy_params)
end # validate_and_get_params()

# Merge in the manifest defined parameters, other stack resources and the params from the template
# Returns out an array we can pass to create_stack or update_stack
def populate_parameters(manifest, params, resources)
	deploy_params = [] # define empty array to be returned

	# Process each parameter the template asks for
	params.each do |p|
		key = p.parameter_key
		# puts "Looking for #{key} in manifest"
		if manifest['SourcedParameters'] != nil && manifest['SourcedParameters'][key]
			(stack, section, stack_key) = manifest['SourcedParameters'][key].split(".")
			if resources[stack][section][stack_key].nil?
				puts "Cant find #{stack_key} from #{stack} for stack param #{key}. Aborting...."
				exit 1
			else
				value = resources[stack][section][stack_key]
			end
		end
		# Manifest Parameters override SourcedParameters.
		if manifest['Parameters'][key]
			# puts "Found #{key} in manifest. Value: #{manifest['Parameters'][key]}"
			value = manifest['Parameters'][key]
		end

		# New feature - key=value on the command line override any other parameters
		if ARGV != nil
			ARGV.each do |arg|
				(k,v) = arg.split("=")
				value = v if k == key
			end
		end

		# we either found it or didn't
		if value.nil?
			# Is there a default?
			# Turns out, with conditions, we might want null variables
			# if p.default_value.nil? || p.default_value.empty? # || p.default_value == "-"
			# 	puts "ERROR: unable to find a value for #{key}, and no valid default. Aborting"
			# 	exit 1
			# end
			puts "WARNING: unable to find a value for #{key}, and no valid default.".yellow
		else
			dp = {
				parameter_key: key,
				parameter_value: value.to_s,
				use_previous_value: false
			}
			deploy_params.push(dp)
		end

	end

	return deploy_params
end #populate_parameters


def create_changeset(changeset_name)
	manifest = get_manifest()
	puts "Generating changeset for " + manifest['StackName'] + " in region " + manifest['Region']
	cf_client = Aws::CloudFormation::Client.new(region: manifest['Region'], profile: ENV['AWS_DEFAULT_PROFILE'])

	stack = get_stack(manifest['StackName'], manifest['Region'], cf_client)
	if stack.nil?
		puts "No such Stack in region " + manifest['Region'] + ". Aborting...."
		exit 1
	else
		template_body = get_template(manifest, cf_client)
		deploy_params = get_deploy_params(manifest, cf_client, template_body)

		# build the command
		command = {
		  stack_name: manifest['StackName'],
		  parameters: deploy_params,
		  capabilities: ["CAPABILITY_NAMED_IAM", "CAPABILITY_IAM"], # accepts CAPABILITY_IAM
		  change_set_name: changeset_name,
		  description: Options[:create_changeset_description]
		}
		if manifest['S3Template']
			command['template_url'] = manifest['S3Template']
		elsif ( manifest['JsonTemplate'] || manifest['LocalTemplate'] )
			command['template_body'] = template_body
		else
			puts "ERROR: I don't have a template. Aborting.".red
			exit 1
		end
		if manifest['NotificationARN']
			command['notification_arns'] = [ manifest['NotificationARN'] ]
		end

		# Create the change set
		begin
			puts "Creating changeset for #{manifest['StackName']}"
			resp = cf_client.create_change_set(command)
			puts "Created changeset #{changeset_name}: #{resp.id}"
		rescue => e
			puts "Error creating changeset. #{e.message}".red
			exit 1
		end
		describe_changeset(cf_client,manifest, resp.id, :false)
		exit 0
	end
end # generate changeset

def describe_changeset(cf_client, manifest, changeset_name, abort)

	def allowed_update(logical_resource_id, action, stack_policy, replacement)
		stack_policy['Statement'].each do |s|
			next if s['Effect'] == "Allow"
			s['Resource'].each do |r|
				regex = String.new(r)
				regex.prepend('^')
				regex = regex + '$'
				regex.gsub!("LogicalResourceId/", "")
				regex.gsub!('*', ".+")
				# puts "#{logical_resource_id} - #{regex}"
				if logical_resource_id.match(regex)
					if action == "Remove" && s.action.contains("Update:Delete")
						puts "\t#{logical_resource_id} is prohibited from Deletion by Stack Policy".blue
						return 1
					elsif action == "Modify" && replacement == "True" && s['Action'].include?("Update:Replace")
						puts "\t#{logical_resource_id} is prohibited from Replacement by Stack Policy".blue
						return 1
					end
				end
			end
		end
		return 0
	end # allowed_update()

	# we'll use this to count the number of things that will fail due to stack policy
	policy_violations = 0

	begin
		changeset = cf_client.describe_change_set({ change_set_name: changeset_name, stack_name: manifest['StackName'] })
		policy_json = cf_client.get_stack_policy({ stack_name: manifest['StackName'] })
	rescue  => e
		puts "Error getting changeset or stack policy: #{e.message}".red
		exit 1
	end

	stack_policy = JSON.parse(policy_json.stack_policy_body)
	changeset.changes.each do |c|
		change = c.resource_change
		if change.action == "Modify"
			if change.replacement == "True"
				puts "Replacement of of #{change.logical_resource_id} (#{change.resource_type}): #{change.physical_resource_id}".red
			elsif change.replacement == "False"
				puts "Modification of #{change.logical_resource_id} (#{change.resource_type}): #{change.physical_resource_id}".green
			elsif change.replacement == "Conditional"
				puts "Conditional Replacement of of #{change.logical_resource_id} (#{change.resource_type}): #{change.physical_resource_id}".yellow
			else
				puts "Warning: Invalid replacement status #{change.replacement}".red
				puts "Unknown replacement of #{change.logical_resource_id} (#{change.resource_type}): #{change.physical_resource_id}".red
			end
		elsif change.action == "Add"
			puts "Addition of new resource #{change.logical_resource_id}".green
		elsif change.action == "Remove"
			puts "REMOVAL if #{change.logical_resource_id} #{change.physical_resource_id}".red
		else
			puts "Warning: Invalid change-action #{change.action}".red
		end
		policy_violations += allowed_update(change.logical_resource_id, change.action, stack_policy, change.replacement)
	end

	if policy_violations > 0
		puts "\nChange Set cannot be executed due to Stack Policy Violations.".red
		puts "You must update this stack using the normal means"
		exit 1 if abort
	elsif changeset.execution_status == "AVAILABLE"
		puts "\nChangeSet AVAILABLE for execution".green
	else
		puts "\nChangeset in execution_status: #{changeset.execution_status}".blue
		puts "Status: #{changeset.status} Reason: #{changeset.status_reason}".blue
	end
	# puts changeset.to_hash.to_json
end

def execute_changeset(cf_client, manifest, changeset_name)
	#  stack_policy_during_update_body: "StackPolicyDuringUpdateBody",
	puts "Executing changeset #{changeset_name} on stack #{manifest['StackName']}"
	begin
		changeset = cf_client.execute_change_set({ change_set_name: changeset_name, stack_name: manifest['StackName'] })
		wait_for_stack_to_complete(manifest['StackName'], manifest['Region'], cf_client)
	rescue  => e
		puts "Error executing changeset: #{e.message}".red
		exit 1
	end
	exit 0
end

def list_changesets(cf_client, manifest)
	resp = cf_client.list_change_sets({ stack_name: manifest['StackName'] })
	resp.summaries.each do |c|
		puts "#{c.change_set_name} (#{c.status}) ExecutionStatus: #{c.execution_status} Created: #{c.creation_time.getlocal}: #{c.description}"
	end
	exit 0
end

# Main routine to deploy the stack
def deploy_stack()

	manifest = get_manifest()
	puts "Deploying " + manifest['StackName'] + " to region " + manifest['Region']
	cf_client = Aws::CloudFormation::Client.new(region: manifest['Region'], profile: ENV['AWS_DEFAULT_PROFILE'])

	stack = get_stack(manifest['StackName'], manifest['Region'], cf_client)
	if stack.nil?
		puts "No such Stack in region " + manifest['Region'] + ". I will create it"
		action="create"
	else
		action="update"
		if ! ResourceGoodStatus.include?(stack.stack_status) && ! Options[:force]
			puts "ERROR: Stack is in status #{stack.stack_status} and cannot be modified".red
			exit 1
		end
	end

	template_body = get_template(manifest, cf_client)
	deploy_params = get_deploy_params(manifest, cf_client, template_body)

	# Here we execute a PreInstall Script
	if manifest['PreInstallScript']
		execute_preinstall(cf_client, manifest, deploy_params)

		# Exit now if we've been asked to only run the pre-install script.
		if Options[:preinstall]
			exit 0
		end
	end

	# Ok, now we create/update the stack
	update_create_stack(manifest, deploy_params, template_body, action, cf_client)

	if ! Options[:dryrun]
		# Now we wait for the operation to complete
		stack_status = wait_for_stack_to_complete(manifest['StackName'], manifest['Region'], cf_client)
		if StackGoodStatus.include?(stack_status)
			# Now execute the post-install script
			execute_postinstall(cf_client, manifest, action)
		end
	end
end #deploy_stack

# Substitute any outputs into the post install from the Manifest
# then execute it
def execute_postinstall(cf_client, manifest, action)
	stack = get_stack(manifest['StackName'], manifest['Region'], cf_client)
	outputs=stack.outputs

	if action == "create"
		if manifest['PostInstallScript']
			script_body = manifest['PostInstallScript']
		else
			return
		end
	elsif action == "update"
		if manifest['PostUpdateScript']
			script_body = manifest['PostUpdateScript']
		else
			return
		end
	else
		puts "ERROR: Invalid action in execute_postinstall".red
		return 1
	end
	outputs.each do |o|
		key = "{{" + o.output_key + "}}"
		script_body.gsub!(key, o.output_value)
	end

	# puts script_body
	# exit 1

	script_filename="/tmp/#{manifest['StackName']}-postscript.sh"
	script = open(script_filename, 'w')
	script.truncate(0)
	script.write(script_body)
	script.close

	puts "Executing Post Install Script"
	system("chmod 700 #{script_filename}")
	system(script_filename)
	system("rm #{script_filename}")
end #execute_postinstall()



# return the stack specified by stack_name
# Will barf if there are multiple stacks with the same name
def get_stack(stack_name, region, cf_client)
	# Does this stack exist in my region?
	begin
		resp = cf_client.describe_stacks({ stack_name: stack_name})
		# Make sure resp.stacks[] has only 1
		if resp.stacks.length > 1
			puts "ERROR: Multiple Stacks with name #{stack_name} exist in #{region}".red
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


# Given a stack_name, return a hash of all the resources with the logical id as the
# key and the physical resource id as the value
def get_stack_resources(stack_name, cf_client)
	my_stack = {}

	# Get the resources from describe_stack_resources()
	begin
		resource_resp = cf_client.describe_stack_resources({ stack_name: stack_name })
		resources = resource_resp.stack_resources
		my_resources = {}
		# resort it as key=value
		resources.each do |r|
			# But only pass along resources with good status
			if ResourceGoodStatus.include?(r.resource_status)
				my_resources[r.logical_resource_id] = r.physical_resource_id
			else
				puts r.logical_resource_id + " is in bad status: " + r.resource_status
			end
		end
		my_stack['Resources'] = my_resources
	rescue Exception => e
		puts "Error finding " + stack_name + " for its resources: " + e.message
		exit 1
		# puts e.inspect
	end
	# Now get the output and parameters from describe_Stacks()
	begin
		my_params = {}
		my_outputs = {}
		stack_resp = cf_client.describe_stacks({ stack_name: stack_name })

		# resort it as key=vale
		stack_resp.stacks[0].parameters.each do |p|
			my_params[p.parameter_key] = p.parameter_value
		end

		stack_resp.stacks[0].outputs.each do |o|
			my_outputs[o.output_key] = o.output_value
		end

		my_stack['Parameters']=my_params
		my_stack['Outputs']=my_outputs
	rescue Exception => e
		puts "Error finding " + stack_name + " for its Parameters and Outputs: " + e.message
		exit 1
	end
	return my_stack
end

# Perform the actual update or create
def update_create_stack(manifest, parameters, template_body, action, cf_client)

	if action == "create"
		# Format the tags the way Amazon wants them
		tags = []
		manifest['Tags'].each do |t|
			x = {
				key: t[0],
				value: t[1].to_s,
			}
			tags.push(x)
		end
	end


	# build the command
	command = {
	  stack_name: manifest['StackName'],
	  template_body: template_body,
	  parameters: parameters,
	  capabilities: ["CAPABILITY_NAMED_IAM", "CAPABILITY_IAM"], # accepts CAPABILITY_IAM
	}
	if manifest['S3Template']
		command['template_url'] = manifest['S3Template']
	elsif ( manifest['JsonTemplate'] || manifest['LocalTemplate'] )
		command['template_body'] = template_body
	else
		puts "ERROR: I don't have a template. Aborting.".red
		exit 1
	end
	if manifest['NotificationARN']
		command['notification_arns'] = [ manifest['NotificationARN'] ]
	end

	# Things we don't yet have in the create/update
		# disable_rollback: manifest['DisableRollback'],
		# resource_types: ["*"],
		# use_previous_template: true,

	# This creates the Stackpolicy from the manifest
	stack_policy = {}
	stack_policy['Statement'] = manifest['StackPolicy']
	stack_policy_json = JSON.generate(stack_policy)
	# command['stack_policy_body'] = stack_policy_json

	if action == "create"
		command['timeout_in_minutes'] = manifest['TimeOut'].to_i
		command['tags'] = tags
		command['on_failure'] = manifest['OnFailure']
		command['stack_policy_body'] = stack_policy_json
	end

	if action == "update"
		command['stack_policy_during_update_body'] = generate_update_stack_policy(manifest, cf_client)
		if Options[:update_policy]
			command['stack_policy_body'] = stack_policy_json
		end
	end

	DebugLog.write("Command to issue for action #{action}: " + command.inspect + "\n\n\n") if Options[:debug]

	if ! Options[:dryrun]
		begin
			if action == "create"
				puts "Creating stack #{manifest['StackName']}"
				resp = cf_client.create_stack(command)
			elsif action == "update"
				puts "Updating stack #{manifest['StackName']}"
				resp = cf_client.update_stack(command)
			else
				puts "ERROR: Action is undefined. Aborting".red
				exit 1
			end
			puts "Stack #{action} id is #{resp.stack_id}"
		rescue Aws::CloudFormation::Errors::ServiceError => e
			if e.message == "No updates are to be performed.".yellow
				puts e.message + " Exiting...."
				exit 0
			end
			puts "ERROR when #{action} #{manifest['StackName']}: #{e.message}".red
			exit 1
		end
	else
		puts "Dry Run Selected. Not issuing Command"
	end
end # update_create_stack()

def get_colorized_resource_status(status)
	if ResourceGoodStatus.include?(status)
		color_status=status.green
	elsif ResourceBadStatus.include?(status)
		color_status=status.red
	else
		color_status=status.yellow
	end
	return color_status
end

def get_colorized_stack_status(status)
	if StackGoodStatus.include?(status)
		color_status=status.green
	elsif StackDoneStatus.include?(status)
		color_status=status.red
	else
		color_status=status.yellow
	end
	return color_status
end

def wait_for_stack_to_complete(stack_name, region, cf_client)
	puts "Now waiting for stack completion"
	next_token = "0"

	begin
		status="N/A"
		# stack = get_stack(stack_name, region, cf_client)
		# status=stack.stack_status
		while StackTempStatus.include?(status)
			stack = get_stack(stack_name, region, cf_client)
			exit 1 if ! stack # Stack was deleted
			status=stack.stack_status
			resp = cf_client.describe_stack_events({ stack_name: stack_name, next_token: next_token })
			puts "\e[H\e[2J" # Clear the screen
			resp.stack_events.reverse.each do |event|
				#Ignore all events that occurred more than 20 minutes ago
				next if event.timestamp < (Time.now.getutc - 20*60)
				color_status=get_colorized_resource_status(event.resource_status)
				puts "#{event.timestamp} #{color_status} #{event.logical_resource_id} (#{event.resource_type}): #{event.resource_status_reason}"
			end
			# next_token = resp.next_token
			color_stack_status=get_colorized_stack_status(status)
			puts "\n#{Time.now.getutc} Stack Status: #{color_stack_status}"
			sleep 10 if StackTempStatus.include?(status)
		end
		# color_stack_status=get_colorized_stack_status(status)
		# puts "Done Waiting: #{color_stack_status}"
		return status
	rescue Seahorse::Client::NetworkingError => e
		puts "Sorry, network error while waiting for stack completion. Error: #{e.message}"
		puts "You can wait for the stack to finish and manually execute the post install or post update script"
		puts "Have a nice day....."
		exit 1
	rescue Aws::CloudFormation::Errors::ServiceError => e
		puts "ERROR: Unable to get status or resources of #{stack_name}: #{e.message}".red
	end
end # end wait_for_stack_to_complete

# Generate the stack Policy we will use to create/update
# TODO: manage overriding the policy on update
def generate_update_stack_policy(manifest, cf_client)

	return nil if ! Options[:allow_update]

	# puts "Stack Policy Override Still not implemented correctly"
	# return nil
	puts "Overriding Stack Policy protections on #{Options[:allow_update]}"

	# we must first start with the existing policy, the override
	policy_json = cf_client.get_stack_policy({ stack_name: manifest['StackName'] })
	stack_policy = JSON.parse(policy_json.stack_policy_body)

	Options[:allow_update].each do |logical_resource_id|

		# # We must remove the approved resource from the existing policy because deny trumps an allow
		stack_policy['Statement'].each do |s|
			next if s['Effect'] == "Allow"
			s['Resource'].each do |r|
				regex = String.new(r)
				regex.prepend('^')
				regex = regex + '$'
				regex.gsub!("LogicalResourceId/", "")
				regex.gsub!('*', ".+")
				# puts "#{logical_resource_id} - #{regex}"
				if logical_resource_id.match(regex)
					s['Resource'].delete(r)
				end
			end
		end

		policy = {}
		policy['Effect'] = "Allow"
		policy['Action'] = ['Update:Modify', 'Update:Delete', 'Update:Replace']
		policy['Principal'] = "*"
		policy['Resource'] = "LogicalResourceId/#{logical_resource_id}"
		stack_policy['Statement'].insert(0, policy)
	end
 	stack_policy_json = JSON.generate(stack_policy)
 	# puts stack_policy_json
	return stack_policy_json
end # generate_update_stack_policy

def print_stack_cost(manifest, cf_client, template_body, deploy_params)
	command = {
	  parameters: deploy_params,
	}
	if manifest['S3Template']
		command['template_url'] = manifest['S3Template']
	elsif ( manifest['JsonTemplate'] || manifest['LocalTemplate'] )
		command['template_body'] = template_body
	else
		puts "ERROR: I don't have a template. Aborting.".red
		exit 1
	end
	# Now issue the call
	begin
		resp = cf_client.estimate_template_cost(command)
		puts "Calculator URL: #{resp.url}"
		exit 0
	rescue Exception => e
		puts "ERROR: #{e.message}".red
	end
end


# Substitute any outputs into the post install from the Manifest
# then execute it
def execute_postinstall(cf_client, manifest, action)
	stack = get_stack(manifest['StackName'], manifest['Region'], cf_client)
	outputs=stack.outputs

	if action == "create"
		if manifest['PostInstallScript']
			script_body = manifest['PostInstallScript']
		else
			return
		end
	elsif action == "update"
		if manifest['PostUpdateScript']
			script_body = manifest['PostUpdateScript']
		else
			return
		end
	else
		puts "ERROR: Invalid action in execute_postinstall".red
		return 1
	end
	outputs.each do |o|
		key = "{{" + o.output_key + "}}"
		script_body.gsub!(key, o.output_value)
	end

	# puts script_body
	# exit 1

	script_filename="/tmp/#{manifest['StackName']}-#{manifest['Region']}-postscript.sh"
	script = open(script_filename, 'w')
	script.truncate(0)
	script.write(script_body)
	script.close

	puts "Executing Post Install Script"
	system("chmod 700 #{script_filename}")
	# Execute the script and delete if it returns 0.
	if system(script_filename)
		system("rm #{script_filename}")
	else
		puts "Script failed to run. you can find it at #{script_filename}"
	end
end #execute_postinstall()

# Execute a Pre-Install Script. Useful if you need to zip up some Lambdas or something
# items inside {{ }} are populated from parameters, either explicitly defined, or sourced from another stack
def execute_preinstall(cf_client, manifest, parameters)

	# puts parameters.inspect
	script_body = manifest['PreInstallScript']
	parameters.each do |p|
		# puts p[:parameter_key]
		key = "{{" + p[:parameter_key].to_s + "}}"
		script_body.gsub!(key, p[:parameter_value].to_s)
	end

	if ! Options[:dryrun]
		script_filename="/tmp/#{manifest['StackName']}-preinstall.sh"
		script = open(script_filename, 'w')
		script.truncate(0)
		script.write(script_body)
		script.close

		puts "Executing Pre Install Script"
		system("chmod 700 #{script_filename}")
		# Fail to proceed if the Preinstall fails to return true.
		# I suggest using the -e option to bash in your manifest
		if system(script_filename)
			system("rm #{script_filename}")
		else
			puts "Pre Install Failed. Aborting".red
			puts "Script executed not removed: #{script_filename}"
			exit 1
		end
	elsif Options[:verbose]
		puts "Dry-Run PreInstallScript: "
		puts script_body
		puts
	end
end #execute_preinstall()

# Pass the template to AWS to validate it
def validate_template(file)
	rc = 1
	template_body = File.read(file)
	cf_client = Aws::CloudFormation::Client.new(profile: ENV['AWS_DEFAULT_PROFILE'])
	begin
		cf_client.validate_template({template_body: template_body})
		# If here we're good
		puts "Template is valid"
		rc = 0
	rescue Exception => e
		puts "ERROR: Can't validate template: #{e.message}".red
		rc = 1
	end
	return rc
end

# Generate a manifest file from a template
def generate_manifest(template_file)

	cf_client = Aws::CloudFormation::Client.new(region: ENV['AWS_DEFAULT_REGION'], profile: ENV['AWS_DEFAULT_PROFILE'])

	begin
		if template_file.start_with?("https://")
			resp = cf_client.validate_template({template_url: template_file})
			template_type = "S3Template"
		else
			template_body = File.read(template_file)
			resp = cf_client.validate_template({template_body: template_body})
			template_type = "LocalTemplate"

		end
		stack_params = resp.parameters
		pp stack_params.inspect if Options[:debug]
	rescue Exception => e
		puts "ERROR: Unable to validate the template: #{e.message} Aborting"
		exit 1
	end

	todays_date=`date`
	puts <<-EOH
# deploy_stack.rb Manifest file generated from #{template_file} on #{todays_date}

# These control how and where the cloudformation is executed
StackName: CHANGEME
OnFailure: DO_NOTHING # accepts DO_NOTHING, ROLLBACK, DELETE
Region: us-east-1
TimeOut: 15m
# You must specify LocalTemplate or S3Template but not both.
#{template_type}: #{template_file}

# Paramaters:
# There are two kinds of parameters, regular and sourced.
# Regular parameters are static and defined in the Parameters: section of this yaml file
# Sourced are parameters that cfnDeploy will go and fetch from other Stacks.
# This simple Serverless app does not depend on any other stacks. However if we start using VPC based
# Lambdas, or have multiple stacks that need to interact, we will want to use Sourced Parameters

###########
# Parameters to the cloudformation stack that are defined manually.
###########
Parameters:
	EOH

	sorted_params = stack_params.sort_by { |a| [a.parameter_key]}
	sorted_params.each do |p|

		# Lots of folks use the "-" for a non-defined paramater. Yaml no likey.
		p.default_value = "" if p.default_value === "-"

		puts "  # #{p.description}"
		puts "  #{p.parameter_key}: #{p.default_value}"
		puts ""
	end

	puts <<-EOH

###########
# These stacks are needed by the SourcedParameters section
###########
DependsOnStacks:
    # - MyOtherStack

###########
# Parameters that come from other deployed stacks.
# Valid Sections are Resources, Outputs Parameters
#
# Hint. Get your list of resources this way:
# aws cloudformation describe-stack-resources --stack-name MSC-DEV-VPC-EAST-1 --output text | awk '{print $2, " ", $3, " " $5}'
###########
SourcedParameters:
  # The Pre-install script needs this to sed into the lambda ARN.
  # pVPCID: MyOtherStack.Outputs.VPCID

###########
# Tags that apply to the stack. Will be inherited by some resources.
###########
Tags:
  Name: StackNameChangeMe
  creator: you@yourcompany.com

###########
# Stack Policies protect resources from accidential deletion or replacement
# for the definition of stack policies see:
# see http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/protect-stack-resources.html#stack-policy-reference
###########
StackPolicy:
    # All other resources should be modifiable.
  - Resource: "*"
    Effect: Allow
    Principal: "*"
    Action:
      - "Update:Modify"
      - "Update:Delete"
      - "Update:Replace"


# Preinstall script will build the zip upload the Lambda code to the S3 bucket
# Anything inside a {{ }} is a stack parameter (Regular or Sourced)
# PreInstallScript: |
#   #!/bin/bash -xe

# PostInstall and PostUpdate Script. Anything inside {{ }} is replaced by an stack output
# PostInstallScript: |
#   #!/bin/bash -xe

# PostUpdateScript: |
#   #!/bin/bash -xe


# End of Manifest
      EOH

	exit 0
end

if Options[:debug]
	DebugLog = open(Options[:debug], 'w')
	DebugLog.truncate(0)
end

if Options[:generate]
	generate_manifest(Options[:generate])
	exit 0
end

if Options[:create_changeset]
	create_changeset(Options[:create_changeset])
	exit 0
end

if Options[:describe_changeset]
	manifest = get_manifest()
	cf_client = Aws::CloudFormation::Client.new(region: manifest['Region'], profile: ENV['AWS_DEFAULT_PROFILE'])
	describe_changeset(cf_client, manifest, Options[:describe_changeset], :false)
	exit 0
end

if Options[:execute_changeset]
	manifest = get_manifest()
	cf_client = Aws::CloudFormation::Client.new(region: manifest['Region'], profile: ENV['AWS_DEFAULT_PROFILE'])
	describe_changeset(cf_client, manifest, Options[:execute_changeset], :true)
	execute_changeset(cf_client, manifest, Options[:execute_changeset])
	exit 0
end

if Options[:delete_changeset]
	manifest = get_manifest()
	cf_client = Aws::CloudFormation::Client.new(region: manifest['Region'], profile: ENV['AWS_DEFAULT_PROFILE'])
	cf_client.delete_change_set({
		change_set_name: Options[:delete_changeset],
		stack_name: manifest['StackName'],
	})
	exit 0
end

if Options[:list_changesets]
	manifest = get_manifest()
	cf_client = Aws::CloudFormation::Client.new(region: manifest['Region'], profile: ENV['AWS_DEFAULT_PROFILE'])
	list_changesets(cf_client, manifest)
	exit 0
end

# Re-Do the Post Install and exit if that's what's requested
if Options[:postinstall]
	manifest = get_manifest()
	puts "Re-Executing Post Install for " + manifest['StackName'] + " in region " + manifest['Region']
	cf_client = Aws::CloudFormation::Client.new(region: manifest['Region'], profile: ENV['AWS_DEFAULT_PROFILE'])
	execute_postinstall(cf_client, manifest, Options[:postinstall])
	exit 0
end

# Return a link to a pricing calculator for the stack and its params
if Options[:price]
	manifest = get_manifest()
	puts "Getting Price for " + manifest['StackName'] + " in region " + manifest['Region']
	cf_client = Aws::CloudFormation::Client.new(region: manifest['Region'], profile: ENV['AWS_DEFAULT_PROFILE'])
	template_body = get_template(manifest, cf_client)
	deploy_params = get_deploy_params(manifest, cf_client, template_body)
	print_stack_cost(manifest, cf_client, template_body, deploy_params)
	exit 0
end

if Options[:test]
	rc = validate_template(Options[:test])
	exit rc
end

# If no special options are given, just deploy/update the stack
deploy_stack()

