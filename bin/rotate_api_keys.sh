#!/bin/bash -e
#
# Rotates your AWS API Keys
# Gets a new one, updates your keychain, then disables the old one. 
# Use this with the aws_account script.

ACCOUNT=$AWS_DEFAULT_PROFILE

if [ -z "$ACCOUNT" ] ; then
	echo "AWS_DEFAULT_PROFILE not set. Will not proceed."
	echo "Have you run . ./aws_account.sh ?"
	exit 1
fi

# we need to remember our old key to delete it
OLD_KEY=$AWS_ACCESS_KEY_ID

# So you can't have more than two access keys. What we will do here is remove any inactive keys, 
# but only if you're at the limit
key_count=`aws iam list-access-keys --output=text | wc -l`
if [ $key_count -gt 1 ] ; then
	# Find the ID of the inactive key
	ID_TO_DELETE=`aws iam list-access-keys --output=text | grep Inactive | awk '{print $2}'`
	if [ ! -z "$ID_TO_DELETE" ] ; then
		echo "Deleting Inactive key $ID_TO_DELETE"
		aws iam delete-access-key --access-key-id $ID_TO_DELETE
		if [ $? -ne 0 ] ; then
			echo "Unable to delete inactive key $ID_TO_DELETE. Clean up by hand please"
			exit 1
		fi
	else
		echo "More than two keys present, and I could not find an inactive key to delete. I cannot proceed"
		exit 1
	fi
# else nothing, there is room to make a new key
fi

echo "About to create your new key. Hold on tight."
# Output of next command looks like
#ACCESSKEY	AKIAIUTXXXXXXX2UJQ	2015-11-18T17:37:51.294Z	/ktVTJwTRPlXXXXXXX9gX6wCVFG	Active	test_user
ACCOUNT_CREDS=`aws iam create-access-key --output=text`
if [ $? -ne 0 ] ; then
	echo "Failed to create a new key. Aborting now"
	exit 1
fi

# Reuse the existing AWSUSER if present. Otherwise use the IAM Username returned from CreateAccessKey
if [ -z $AWSUSER ] ; then
	AWSUSER=`echo $ACCOUNT_CREDS | awk '{print $NF}' `
fi

export AWS_ACCESS_KEY_ID=`echo $ACCOUNT_CREDS | awk '{print $2}' `
export AWS_SECRET_ACCESS_KEY=`echo $ACCOUNT_CREDS | awk '{print $4}' `

if [ -z "$AWSUSER" ] || [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] ; then
	echo "Unable to get all the right vars from AWS. Unable to proceed."
	exit 1
fi

echo "Adding new credentials for $AWS_ACCESS_KEY_ID to OSX Keychain"
KEYCHAIN_ENTRY="${AWSUSER}@${AWS_DEFAULT_PROFILE}"
security add-generic-password -U -c AWSK -D AWS_ACCESS_KEY_ID -a AWS_ACCESS_KEY_ID -s $KEYCHAIN_ENTRY -w $AWS_ACCESS_KEY_ID -T /usr/bin/security
security add-generic-password -U -c AWSK -D AWS_SECRET_ACCESS_KEY -a AWS_SECRET_ACCESS_KEY -s $KEYCHAIN_ENTRY -w $AWS_SECRET_ACCESS_KEY

echo -n "Added AWS_ACCESS_KEY_ID for $AWSUSER in $ACCOUNT: "
security find-generic-password -a AWS_ACCESS_KEY_ID -s $KEYCHAIN_ENTRY -w
echo -n "Added AWS_SECRET_ACCESS_KEY for $AWSUSER in $ACCOUNT (truncated for security): "
security find-generic-password -a AWS_SECRET_ACCESS_KEY -s $KEYCHAIN_ENTRY -w | cut -c1-30

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

echo "Waiting 30 seconds for your new key to take effect before I can shutdown the old one"
sleep 30

# Final action needs to be deactivation of my old key
ID_TO_DELETE=`aws iam list-access-keys --output=text | grep $OLD_KEY | awk '{print $2}'`
if [ ! -z "$ID_TO_DELETE" ] ; then
	echo "Deactivating your current key ($ID_TO_DELETE)."
	aws iam update-access-key --access-key-id $ID_TO_DELETE --status Inactive
	if [ $? -ne 0 ] ; then
		echo "Unable to deactivate old key $ID_TO_DELETE. Clean up by hand please"
		exit 1
	fi
else
	echo "Could not find an old key to deactivate. That's really weird."
	exit 1
fi
aws iam list-access-keys --output=text

echo "All done. Please exit all open AWS management windows as your keys no longer work."




