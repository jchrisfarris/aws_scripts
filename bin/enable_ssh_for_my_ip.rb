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
  opts.on("-r", "--revoke", "revoke my access") do |r|
    options[:revoke] = r
  end
  opts.on("-i", "--ip ip", "use this IP instead") do |ip|
    options[:ip] = ip
  end
  opts.on("-p", "--port port", "use this port instead of 22") do |port|
    options[:port] = port
  end
  opts.on("-R", "--revoke-all", "Revoke All SSH Access") do |all|
    options[:revokeall] = all
  end

end.parse!

# p options
# p ARGV


if options[:port]
	port = options[:port]
else
	port = 22
end

if options[:ip] == nil
	public_ipv4=`curl -s http://myexternalip.com/raw`
	public_ipv4.chomp!
else
	public_ipv4=options[:ip]
end

if ENV['AWS_SECRET_ACCESS_KEY'] == ""
	puts "Your Keys are not in the environment. Failing to do anything"
	exit
end


instance_name=ARGV[0]


permission={ ip_permissions: [
			{ 	ip_protocol: "tcp",
				from_port: port,
				to_port: port,
				ip_ranges: [ { cidr_ip: "#{public_ipv4}/32" } ]
			} ] }

ec2=Aws::EC2::Client.new()

begin
	result=ec2.describe_instances({filters: [ { name: "tag:Name", values: [ "#{instance_name}" ] }, { name: "instance-state-name", values: ['running']} ] } )
	# puts result.reservations.inspect
	if result.reservations.length == 0
		puts "Could not find #{instance_name}"
		exit 1
	end
rescue Aws::EC2::Errors::AuthFailure => e
	puts "Auth Failure: #{e.message}. Are you keys loaded?"
	exit 1
end


i=result.reservations[0].instances[0]
sg_id = i.security_groups[0].group_id

sg=Aws::EC2::SecurityGroup.new(sg_id)
if options[:revokeall]
	puts "Revoking all #{port} Access to instance #{instance_name} (ID: #{i.instance_id})"
	sg.ip_permissions.each do |p|
		if p.from_port == port && p.to_port == port
			permission[:ip_permissions][0][:ip_ranges]=p.ip_ranges
			p.ip_ranges.each do |r|
				r.cidr_ip
				puts "Revoking #{r.cidr_ip}"
			end
			r=sg.revoke_ingress(permission)
		end
	end
else
	begin
		if options[:revoke]
			puts "Revoking #{port} for Instance #{instance_name} (ID: #{i.instance_id}) by removing #{public_ipv4} from #{sg_id}"

			r=sg.revoke_ingress(permission)
		else
			puts "Authorizing #{port} for Instance #{instance_name} (ID: #{i.instance_id}) by adding #{public_ipv4} to #{sg_id}"
			r=sg.authorize_ingress(permission)
		end
		puts "Done" if r.successful?

	rescue Aws::EC2::Errors::ServiceError => e
		puts "Failure: " + e.message
	end
end

