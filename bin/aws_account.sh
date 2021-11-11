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
	export AWS_PROFILE=$1

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
	unset AWS_SESSION_TOKEN

	if [ -z $AWS_SECRET_ACCESS_KEY ] ; then
	  echo "Unable to find the secret in the keychain"
	  return 1
	fi

	# Set the prompt so you know what you're doing
	export COLOR="32m"
	export PS1="\[\033[$COLOR\][\u@\h \W] $AWSUSER@$AWS_DEFAULT_PROFILE ($AWS_DEFAULT_REGION):\[\033[0m\] "
}

aws_profile () {
	if [ -z $1 ] ; then
	  echo "Usage: aws_profile <aws_profile> <region>"
	  return 1
	fi

	# Escape the ][ lest you are using a regex. eek
	grep "\[profile $1\]" ~/.aws/config > /dev/null 2>&1
	if [ $? != 0 ] ; then
	  echo "Invalid profile. Check the files in ~/.aws/config"
	  return 1
	fi

	echo "Using $1 as my AWS Account"
	# Allow you to not need that dang --profile on each command
	export AWS_DEFAULT_PROFILE=$1
	export AWS_PROFILE=$1

	if [ ! -z "$2" ] ; then
		export AWS_DEFAULT_REGION="$2"
	else
		export AWS_DEFAULT_REGION="us-east-1"
	fi

	# Remove any existing environment keys
	unset AWS_SECRET_ACCESS_KEY
	unset AWS_ACCESS_KEY_ID
	unset AWS_SESSION_TOKEN

	# Set the prompt so you know what you're doing
	export COLOR="94m"
	export PS1="\[\033[$COLOR\][\u@\h \W] @$AWS_DEFAULT_PROFILE ($AWS_DEFAULT_REGION):\[\033[0m\] "
}


aws_mfa () {
	if [ -z $1 ] ; then
	  echo "Usage: aws_mfa <aws_profile> <region>"
	  return 1
	fi

	echo "Using $1 as my AWS Account"
	# Allow you to not need that dang --profile on each command
	export AWS_DEFAULT_PROFILE=$1
	export AWS_PROFILE=$1

	if [ ! -z "$2" ] ; then
		export AWS_DEFAULT_REGION="$2"
	else
		export AWS_DEFAULT_REGION="us-east-1"
	fi

	# Escape the ][ lest you are using a regex. eek
	grep "\[profile $1\]" ~/.aws/config > /dev/null 2>&1
	if [ $? != 0 ] ; then
	  echo "Invalid profile. Check the files in ~/.aws/config"
	  return 1
	fi

	# Set the prompt so you know what you're doing
	export COLOR="32m"
	export PS1="\[\033[$COLOR\][\u@\h \W] $AWSUSER@$AWS_DEFAULT_PROFILE ($AWS_DEFAULT_REGION):\[\033[0m\] "
}

# Lets export a function that makes it easy to change my local region
ch_region () {

	if [ "$1" == "" ] ; then
		echo "usage: ch_region <region>"
		return
	fi

	echo "Changing region to $1"
	export AWS_DEFAULT_REGION=$1
	export PS1="\[\033[$COLOR\][\u@\h \W] @$AWS_DEFAULT_PROFILE ($AWS_DEFAULT_REGION):\[\033[0m\] "
}

ch_aws_config () {

	if [ "$1" == "" ] ; then
		echo "usage: ch_aws_config <filename>"
		return
	fi

	export AWS_CONFIG_FILE=~/.aws/$1

	if [ ! -f $AWS_CONFIG_FILE ] ; then
		echo "Cannot find config file $AWS_CONFIG_FILE"
		unset AWS_CONFIG_FILE
		return
	fi

	echo "Changing config file to $AWS_CONFIG_FILE"
	export PS1="\[\033[$COLOR\][\u@\h \W] config-$1@$AWS_DEFAULT_PROFILE ($AWS_DEFAULT_REGION):\[\033[0m\] "
}

# Here are some aliases
alias "li"="aws ec2 describe-instances   --query 'Reservations[*].Instances[*].[Tags[?Key == \`Name\`].Value,InstanceId,State.Name,InstanceType,PublicIpAddress,PrivateIpAddress]' --output text | sed 'N;s/\n/ /'"
alias "list-stacks"="aws cloudformation list-stacks --stack-status-filter CREATE_IN_PROGRESS CREATE_FAILED CREATE_COMPLETE ROLLBACK_IN_PROGRESS ROLLBACK_FAILED ROLLBACK_COMPLETE DELETE_IN_PROGRESS DELETE_FAILED UPDATE_IN_PROGRESS UPDATE_COMPLETE_CLEANUP_IN_PROGRESS UPDATE_COMPLETE UPDATE_ROLLBACK_IN_PROGRESS UPDATE_ROLLBACK_FAILED UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS UPDATE_ROLLBACK_COMPLETE --query 'StackSummaries[*].{Name:StackName,Status:StackStatus}' --output text"
alias "list_regions"="aws ec2 describe-regions --query 'Regions[].[RegionName]' --output text"
alias "cft-find"="aws cloudformation describe-stack-resources --physical-resource-id"
