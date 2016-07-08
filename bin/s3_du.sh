#!/bin/bash

BUCKETNAME=$1

if [ -z "$BUCKETNAME" ] ; then
  echo "usage: $0 <bucketname>"
  exit 1
fi

aws s3api list-objects --bucket $BUCKETNAME --output json --query "[sum(Contents[].Size), length(Contents[])]" | awk 'NR!=2 {print $0;next} NR==2 {print $0/1024/1024/1024" GB"}'
