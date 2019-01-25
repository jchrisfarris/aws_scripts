#!/bin/bash


# Function to set environment after invoking samlkeygen.
# https://github.com/turnerlabs/samlkeygen
# Assumes temp credentials are already generated
aws_saml () {
	if [ -z $1 ] ; then
	  echo "Usage: aws_account <aws_profilee> <region>"
	  return 1
	fi


	CRED_PROFILE=`samlkeygen select-profile $1`
	if [ $? -ne 0 ] ; then
		echo "Unable to file credentials. Aborting"
		return 1
	fi


	echo "Using $CRED_PROFILE as my AWS Account"
	# Allow you to not need that dang --profile on each command
	export AWS_DEFAULT_PROFILE=$CRED_PROFILE
	export AWS_PROFILE=$CRED_PROFILE
	export AWSUSER=$USER

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
	export COLOR="33m"
	export PS1="\[\033[$COLOR\][\u@\h \W] $AWSUSER@$AWS_DEFAULT_PROFILE ($AWS_DEFAULT_REGION):\[\033[0m\] "
}

