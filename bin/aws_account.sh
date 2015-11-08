#!/bin/bash

# This script will pull API keys from OSX Keychain and allow you to easily manage multiple accounts. 

# Each account needs a definition in ~/.aws/config
# specifying the region is optional
#
# [my-account-name]
# region = us-east-1

if [ -z $1 ] ; then
  echo "Usage $0 <aws account> <region>"
  echo "call it with a . ./$0"
  return 1
fi

echo "Using $1 as my AWS Account"

if [ ! -z "$2" ] ; then
	export AWS_REGION="$2"
else
	export AWS_REGION="us-east-1"
fi

# Escape the ][ lest you are using a regex. eek
grep "\[profile $1\]" ~/.aws/config > /dev/null 2>&1
if [ $? != 0 ] ; then
  echo "Invalid profile. Check the files in ~/.aws $?"
  return 1
fi

KEYCHAIN_ENTRY="AWS-$1"

export AWS_ACCESS_KEY_ID=$(security find-generic-password -l $KEYCHAIN_ENTRY -a AWS_KEY -w)
export AWS_SECRET_ACCESS_KEY=$(security find-generic-password -l $KEYCHAIN_ENTRY -a AWS_SECRET_KEY -w) 

if [ -z $AWS_SECRET_ACCESS_KEY ] ; then
  echo "Unable to find the secret in the keychain"
  return 1
fi

# Allow you to not need that dang --profile on each command
export AWS_DEFAULT_PROFILE=$1

# Set the prompt so you know what you're doing
export COLOR="32m"
export PS1="\[\033[$COLOR\][\u@\h \W] AWS-$1 ($AWS_REGION):\[\033[0m\] "


# Other setup
complete -C /pht/aws/bin/aws_completer aws
export PATH=$PATH:/pht/aws/bin

aws ec2 describe-instances
