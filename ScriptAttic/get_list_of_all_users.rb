#!/usr/bin/ruby


require 'yaml'
require 'json'
require 'aws-sdk-resources'
require 'optparse'
require 'colorize'
require 'pp'

iam_client = Aws::IAM::Client.new(region: 'us-east-1')

begin
	resp = iam_client.list_users(path_prefix: "/")
rescue  => e
	puts "Error getting users #{e.message}"
	exit 1
end

users = resp.users
users.each do |u|
	next if u.path != "/"
	puts u.user_name
end

