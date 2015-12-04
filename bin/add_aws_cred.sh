#!/bin/bash -e
#
# Uploads your AWS Security API Keys to OSX KeyChain. Requires the CSV file you downloaded from the AWS Console. 
# Use this with the aws_account script.

CSV_FILE=$1
ACCOUNT=$2

# Abort if not on a Mac, because WTF
if [ `uname` != "Darwin" ] ; then
	echo "Requires OSX"
	exit 1
fi

if [ ! -f "$CSV_FILE" ] ; then
	echo "Can't open the credentials file. Aborting"
	echo "Usage: $0 credentials.csv account_profile_string"
	exit 1
fi
if [ -z "$ACCOUNT" ] ; then
	echo "You must specify an account string."
	echo "Usage: $0 credentials.csv account_profile_string"
	exit 1
fi

AWSUSER=`tail -1 $CSV_FILE | awk -F, '{print $1}' | sed s/\"//g`
AWS_ACCESS_KEY_ID=`tail -1  $CSV_FILE | awk -F, '{print $2}'`
AWS_SECRET_ACCESS_KEY=`tail -1  $CSV_FILE | awk -F, '{print $3}'`

if [ -z "$AWSUSER" ] || [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] ; then
	echo "Unable to get all the right vars from your credentials file. Unable to proceed."
	exit 1
fi

KEYCHAIN_ENTRY="${AWSUSER}@${ACCOUNT}"
security add-generic-password -c AWSK -D AWS_ACCESS_KEY_ID -a AWS_ACCESS_KEY_ID -s $KEYCHAIN_ENTRY -w $AWS_ACCESS_KEY_ID -T /usr/bin/security
#echo $AWS_SECRET_ACCESS_KEY
security add-generic-password -c AWSK -D AWS_SECRET_ACCESS_KEY -a AWS_SECRET_ACCESS_KEY -s $KEYCHAIN_ENTRY -w "${AWS_SECRET_ACCESS_KEY}"



#echo security add-generic-password -c AWSK -a AWS_ACCESS_KEY_ID -s $KEYCHAIN_ENTRY -w $AWS_ACCESS_KEY_ID -T /usr/bin/security
#echo security add-generic-password -c AWSK -a AWS_SECRET_ACCESS_KEY -s $KEYCHAIN_ENTRY -w $AWS_SECRET_ACCESS_KEY

echo -n "Added AWS_ACCESS_KEY_ID for $AWSUSER in $ACCOUNT: "
security find-generic-password -a AWS_ACCESS_KEY_ID -s $KEYCHAIN_ENTRY -w
echo -n "Added AWS_SECRET_ACCESS_KEY for $AWSUSER in $ACCOUNT (truncated for security): "
security find-generic-password -a AWS_SECRET_ACCESS_KEY -s $KEYCHAIN_ENTRY -w | cut -c1-30

#echo security add-generic-password -c AWSK -a AWS_SECRET_ACCESS_KEY -s $KEYCHAIN_ENTRY -w \"$AWS_SECRET_ACCESS_KEY\"
#echo security find-generic-password -a AWS_SECRET_ACCESS_KEY -s $KEYCHAIN_ENTRY -w 

# This is needed in the ~/.aws/config directory
# Escape the ][ lest you are using a regex. eek
grep "\[profile $2\]" ~/.aws/config > /dev/null 2>&1
if [ $? != 0 ] ; then
	echo "Adding $ACCOUNT to ~/.aws/config - you can add customizations (like default output format) to that file"
  echo "[$ACCOUNT]" >> ~/.aws/config
  echo "" >> ~/.aws/config
fi
