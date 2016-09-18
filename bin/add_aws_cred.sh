#!/bin/bash -e
#
# Prompt for AWS Credentials and stores them in your OSX keychain 
# Use this with the aws_account script.

# Abort if not on a Mac, because WTF
if [ `uname` != "Darwin" ] ; then
	echo "Requires OSX"
	exit 1
fi

echo -n "Please enter the Account Identifier: "
read ACCOUNT
echo -n "Please enter the Access Key: "
read AWS_ACCESS_KEY_ID
echo -n "Please enter the Secret Key: "
read AWS_SECRET_ACCESS_KEY
echo -n "Please enter the user or hit enter for default ($USER): "
read ans 
if [ -z "$ans" ] ; then
	AWSUSER=$USER
else
	AWSUSER=$ans
fi


if [ -z "$AWSUSER" ] || [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] ; then
	echo "Unable to get all the right credentials . Unable to proceed."
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
grep "\[profile $ACCOUNT\]" ~/.aws/config > /dev/null 2>&1
if [ $? -ne 0 ] ; then
	echo "Adding $ACCOUNT to ~/.aws/config - you can add customizations (like default output format) to that file"
	echo "" >> ~/.aws/config
	echo "[profile $ACCOUNT]" >> ~/.aws/config
	echo "" >> ~/.aws/config
fi
