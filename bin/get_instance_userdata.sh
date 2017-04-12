#!/bin/bash

# Given the name of an instance, it will lookup the instance ID and download the UserData.

NAME=$1

if [ -z $NAME ] ; then
  echo "Usage: $0 <instance_name>"
  exit 1
fi

if [ -f "$NAME.userdata" ] ; then
	echo -n "Userdata file exists. Do you want to proceed (Y/N) "
	read ans
	if [ $ans != "Y" ] && [ $ans != "y" ] ; then
		echo "Aborting..."
		exit 1
	fi
fi

# describe instance returns result like the following (fnord is machine name)
# fnord i-092bd1c63d1847df2	running	

INSTANCE=`aws ec2 describe-instances --filter "Name=tag-key,Values=Name" "Name=tag-value,Values=$NAME" \
			--query 'Reservations[*].Instances[*].InstanceId' --output text `


echo "Found InstanceId $INSTANCE for $NAME"

if [ -z $INSTANCE ] ; then
	echo "Unable to find an instance named $NAME"
	exit 1
fi
 
aws ec2 describe-instance-attribute --instance-id $INSTANCE --attribute userData --query '{data:UserData}' \
	--output text | awk '{print $NF}' | base64 -D > $NAME.userdata

echo "SHA Sum of Userdata follows"
cat $NAME.userdata | shasum
 
