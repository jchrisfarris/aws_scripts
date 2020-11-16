#!/bin/bash

if [ -z "$1" ] ; then
	echo "Usage $0 <bucketname>"
	exit 1
fi

aws s3api put-bucket-encryption --bucket $1 --server-side-encryption-configuration \
	'{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'

aws s3api put-public-access-block --bucket $1  --public-access-block-configuration \
	BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

