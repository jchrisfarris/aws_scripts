#!/bin/bash

# Script that will run a command across all regions by appending --region 

REGIONS=`aws ec2 describe-regions --output text | awk '{print $NF}' | sort`

for r in $REGIONS ; do 
	echo "Running $@ --region $r"
	$@ --region $r
done
