#!/bin/bash

buckettoempty=$1

if [ -z "$buckettoempty" ] ; then
	echo "Usage: $0 <buckettoempty>"
	exit 1
fi

# 1: Delete objects
aws s3api delete-objects --bucket ${buckettoempty} --delete "$(aws s3api list-object-versions --bucket ${buckettoempty} --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" --output text

# 2: Delete markers
aws s3api delete-objects --bucket ${buckettoempty} --delete "$(aws s3api list-object-versions --bucket ${buckettoempty} --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" --output text

# 3. Delete Bucket
aws s3 rb s3://${buckettoempty}/ --force
