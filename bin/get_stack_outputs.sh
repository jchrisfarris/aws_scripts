#!/bin/bash

STACK=$1

if [ -z "$STACK" ] ; then
  echo "Usage: $0 <stackname>"
  exit 1
fi

aws cloudformation describe-stacks --stack-name $STACK --output text \
	--query 'Stacks[*].Outputs[*].{OutputKey:OutputKey,OutputValue:OutputValue}'
