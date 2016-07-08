#!/usr/bin/perl

use strict;
use Data::Dumper;
use Net::Amazon::EC2;

 my $ec2 = Net::Amazon::EC2->new(
        AWSAccessKeyId => $ENV{"AWS_ACCESS_KEY_ID"}, 
        SecretAccessKey => $ENV{'AWS_SECRET_ACCESS_KEY'},
        region => $ENV{'AWS_DEFAULT_REGION'}
 );

my $running_instances = $ec2->describe_instances;

if ( ! defined $running_instances ) {
  print "No EC2 Instances running\n";
  exit 1;
}

#print Dumper $running_instances;

 foreach my $reservation (@$running_instances) {
    foreach my $instance ($reservation->instances_set) {
    	my $NAME = "UntaggedInstance";
		my $state = $instance->{instance_state}->{name};
        
        if (defined $instance->{tag_set} ) {
	  		my @tags = @{$instance->{tag_set}};
         	foreach my $tag (@tags) {
         		if ($tag->{key} eq "Name") {
	    		  $NAME = $tag->{value};
	    		}	
          	} # end foreach
        } # end if
        print "$NAME (" . $instance->instance_id . ") is $state - $instance->{private_ip_address} - $instance->{ip_address} - $instance->{instance_type} - Launched: $instance->{launch_time} \n";
    }
 }
