#!/bin/bash

REGIONS=`aws ec2 describe-regions --query Regions[].RegionName --output text`

for r in $REGIONS ; do

	echo "recreating a Default VPC in $r"
	aws ec2 create-default-vpc --region $r

done