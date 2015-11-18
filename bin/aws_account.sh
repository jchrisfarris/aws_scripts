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
# Allow you to not need that dang --profile on each command
export AWS_DEFAULT_PROFILE=$1

if [ ! -z "$2" ] ; then
	export AWS_DEFAULT_REGION="$2"
else
	export AWS_DEFAULT_REGION="us-east-1"
fi

if [ ! -z "$3" ] ; then
	export AWSUSER="$3"
else
	export AWSUSER=$USER
fi

# Escape the ][ lest you are using a regex. eek
grep "\[profile $1\]" ~/.aws/config > /dev/null 2>&1
if [ $? != 0 ] ; then
  echo "Invalid profile. Check the files in ~/.aws/config"
  return 1
fi

KEYCHAIN_ENTRY="AWS-$1"

export AWS_ACCESS_KEY_ID=$(security find-generic-password -s $AWSUSER -l $KEYCHAIN_ENTRY -a AWS_ACCESS_KEY_ID -w)
export AWS_SECRET_ACCESS_KEY=$(security find-generic-password -s $AWSUSER -l $KEYCHAIN_ENTRY -a AWS_SECRET_ACCESS_KEY -w) 

if [ -z $AWS_SECRET_ACCESS_KEY ] ; then
  echo "Unable to find the secret in the keychain"
  return 1
fi

# Set the prompt so you know what you're doing
export COLOR="32m"
export PS1="\[\033[$COLOR\][\u@\h \W] $AWSUSER@AWS-$AWS_DEFAULT_PROFILE ($AWS_DEFAULT_REGION):\[\033[0m\] "


# Other setup
complete -C /pht/aws/bin/aws_completer aws
export PATH=$PATH:/pht/aws/bin

aws ec2 describe-instances --output=text | egrep 'INSTANCES|Name|STATE'

# Lets export a function that makes it easy to change my local region
ch_region () {

	if [ "$1" == "" ] ; then
		echo "usage: ch_region <region>"
		return
	fi

	echo "Changing region to $1"
	export AWS_DEFAULT_REGION=$1
	export PS1="\[\033[$COLOR\][\u@\h \W] AWS-$AWS_DEFAULT_PROFILE ($AWS_DEFAULT_REGION):\[\033[0m\] "

}
