#!/bin/bash -e
#
# Exports your API Keys from OSX Keychain to a CSV file. Helpful if moving between PCs

if [ -z $1 ] ; then
  echo "Usage: aws_account <aws_account_name> <aws_username>"
  exit 1
fi

# echo "Using $1 as my AWS Account"
# Allow you to not need that dang --profile on each command
AWS_DEFAULT_PROFILE=$1


if [ ! -z "$2" ] ; then
	export AWSUSER="$2"
else
	export AWSUSER=$USER
fi


KEYCHAIN_ENTRY="${AWSUSER}@${AWS_DEFAULT_PROFILE}"
# echo $KEYCHAIN_ENTRY
# echo "security find-generic-password -s $KEYCHAIN_ENTRY -a AWS_ACCESS_KEY_ID -w"
# echo "security find-generic-password -s $KEYCHAIN_ENTRY -a AWS_SECRET_ACCESS_KEY -w"
AWS_ACCESS_KEY_ID=$(security find-generic-password -s $KEYCHAIN_ENTRY -a AWS_ACCESS_KEY_ID -w)
AWS_SECRET_ACCESS_KEY=$(security find-generic-password -s $KEYCHAIN_ENTRY -a AWS_SECRET_ACCESS_KEY -w) 

if [ -z $AWS_SECRET_ACCESS_KEY ] ; then
  echo "Unable to find the secret in the keychain"
  return 1
fi

echo "\"${AWSUSER}\",${AWS_ACCESS_KEY_ID},${AWS_SECRET_ACCESS_KEY}"




