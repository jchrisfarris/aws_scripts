#!/usr/bin/perl

use strict;
use Data::Dumper;
use Net::Amazon::EC2;

my $instance_id = $ARGV[0];

my $ec2 = Net::Amazon::EC2->new(
    AWSAccessKeyId => $ENV{"AWS_ACCESS_KEY_ID"}, 
    SecretAccessKey => $ENV{'AWS_SECRET_ACCESS_KEY'},
    region => $ENV{'AWS_DEFAULT_REGION'}
);

print "InstanceID: $instance_id\n";

# Now setting to terminate on shutdown
my $result = $ec2->terminate_instances(
        'InstanceId' => $instance_id,
  );

print "Sleeping 30 to term instance\n";
sleep 30;

my $running_instances = $ec2->describe_instances ( 'InstanceId' => $instance_id, );

