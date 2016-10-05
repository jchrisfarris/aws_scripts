#!/bin/bash

# This script will pull API keys from OSX Keychain and allow you to easily manage multiple accounts. 

# Each account needs a definition in ~/.aws/config
# specifying the region is optional
#
# [my-account-name]
# region = us-east-1


# Function to load the API keys from OSX Keychain.
aws_account () {
	if [ -z $1 ] ; then
	  echo "Usage: aws_account <aws_account_name> <aws_username> <region>"
	  return 1
	fi

	echo "Using $1 as my AWS Account"
	# Allow you to not need that dang --profile on each command
	export AWS_DEFAULT_PROFILE=$1


	if [ ! -z "$2" ] ; then
		export AWSUSER="$2"
	else
		export AWSUSER=$USER
	fi

	if [ ! -z "$3" ] ; then
		export AWS_DEFAULT_REGION="$3"
	else
		export AWS_DEFAULT_REGION="us-east-1"
	fi


	# Escape the ][ lest you are using a regex. eek
	grep "\[profile $1\]" ~/.aws/config > /dev/null 2>&1
	if [ $? != 0 ] ; then
	  echo "Invalid profile. Check the files in ~/.aws/config"
	  return 1
	fi

	KEYCHAIN_ENTRY="${AWSUSER}@${AWS_DEFAULT_PROFILE}"
	echo $KEYCHAIN_ENTRY
	# echo "security find-generic-password -s $KEYCHAIN_ENTRY -a AWS_ACCESS_KEY_ID -w"
	# echo "security find-generic-password -s $KEYCHAIN_ENTRY -a AWS_SECRET_ACCESS_KEY -w"
	export AWS_ACCESS_KEY_ID=$(security find-generic-password -s $KEYCHAIN_ENTRY -a AWS_ACCESS_KEY_ID -w)
	export AWS_SECRET_ACCESS_KEY=$(security find-generic-password -s $KEYCHAIN_ENTRY -a AWS_SECRET_ACCESS_KEY -w) 

	if [ -z $AWS_SECRET_ACCESS_KEY ] ; then
	  echo "Unable to find the secret in the keychain"
	  return 1
	fi

	# Set the prompt so you know what you're doing
	export COLOR="32m"
	export PS1="\[\033[$COLOR\][\u@\h \W] $AWSUSER@$AWS_DEFAULT_PROFILE ($AWS_DEFAULT_REGION):\[\033[0m\] "

	list.pl
}

# Lets export a function that makes it easy to change my local region
ch_region () {

	if [ "$1" == "" ] ; then
		echo "usage: ch_region <region>"
		return
	fi

	echo "Changing region to $1"
	export AWS_DEFAULT_REGION=$1
	export PS1="\[\033[$COLOR\][\u@\h \W] $AWSUSER@AWS-$AWS_DEFAULT_PROFILE ($AWS_DEFAULT_REGION):\[\033[0m\] "

}


# Here are some aliases
alias "li"="aws ec2 describe-instances --output=text --query 'Reservations[].Instances[].{InstanceId:InstanceId,Status:State.Name,Type:InstanceType,PublicIpAddress:PublicIpAddress,PrivateIpAddress:PrivateIpAddress}'"
alias "list-stacks"="aws cloudformation list-stacks --stack-status-filter CREATE_IN_PROGRESS CREATE_FAILED CREATE_COMPLETE ROLLBACK_IN_PROGRESS ROLLBACK_FAILED ROLLBACK_COMPLETE DELETE_IN_PROGRESS DELETE_FAILED UPDATE_IN_PROGRESS UPDATE_COMPLETE_CLEANUP_IN_PROGRESS UPDATE_COMPLETE UPDATE_ROLLBACK_IN_PROGRESS UPDATE_ROLLBACK_FAILED UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS UPDATE_ROLLBACK_COMPLETE --query 'StackSummaries[*].{Name:StackName,Status:StackStatus}' --output text"