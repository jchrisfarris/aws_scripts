#!/bin/bash

# Clean up old CloudTrails & Config Svc prior to re-deploying the CloudTrail & Config Service Cloudformation Stack

REGIONS=`aws ec2 describe-regions --output=text | awk '{print $NF}'`

for r in $REGIONS ; do 
	echo $r
	aws cloudtrail delete-trail --name Default --region $r

	aws configservice describe-configuration-recorders --output text 

	R=`aws configservice describe-configuration-recorders --output text | grep CONFIGURATIONRECORDERS | awk '{print $2}'`
	echo "Deleting config recorder $R"
	aws configservice delete-configuration-recorder --configuration-recorder-name $R  --region $r

	aws configservice describe-delivery-channels --output text
	C=`aws configservice describe-delivery-channels --output text | awk '{print $2}'`
	echo "Deleting delivery channel $C"
	aws configservice delete-delivery-channel --delivery-channel-name $C --region $r


done

