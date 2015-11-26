#!/bin/bash
# This shell script will run a bunch of commands to prep a new AWS Account
# Hat Tip to Alex Tomic for the list of things to do here. 

# Starting a long list of TODOs with this script
# Amazon is about to dump us a bunch of new regions. Make this script do needful only on new regions
# Figure out how to disable use of a region. Is it just the sts service, or other things?
# Maybe move billing bucket to logging bucket.
# can I programatically setup my detailed billing report tags?
# This needs much more idempotency around resources that already exist.
# 


# TODO - Make this whole thing getopts. For now its uncomment the parts you want to run. 
usage() {
	echo "Usage: $0 <domain> <aws_account_number>"
	echo "Options:"
	echo "	--all - Execute all the steps"
	echo "	--detailed_billing - do this thing"
	echo "	--create_admin_group - do this thing"
	echo "	--setup_cloudtrail - do this thing"
	echo "	--setup_configservice - do this thing"
	echo "	--password_policy - do this thing"
	echo "	--status - Show the status of the things this script will setup."
	echo "	--region - Only do thing for this specific region. NOT YET IMPLEMENTED."
	echo "	--policy_document_path - specify where the policy documents from github are: /pht/aws_scripts/policy_documents"
	exit 1
}

# This could get overridden if I need to do this setup on new AWS regions. 
REGIONS=`aws ec2 describe-regions --output=text | awk '{print $NF}'`

# eff GNU, BSD and Apple for not having a standard getopt/getopts that will support --long options. Bah. 
while true ; do
  case "$1" in
  		-h ) echo "Showing Usage:" ; usage ;  exit 0 ;;
		--all ) 
			echo "Doing Everything"
			DO_ALL=TRUE
			shift 
		;;
		--detailed_billing) 
			echo "Doing Billing"
			DO_DETAILED_BILLING=TRUE
			shift 
		;;
		--create_admin_group) 
			echo "Doing Admin Group" 
			DO_CREATE_ADMIN_GROUP=TRUE
			shift 
		;;
		--setup_cloudtrail) 
			echo "Doing Cloud Trail"
			DO_SETUP_CLOUDTRAIL=TRUE
			shift 
		;;
		--setup_configservice) 
			echo "Doing AWS Config Service" 
			DO_SETUP_CONFIGSERVICE=TRUE
			shift 
		;;
		--password_policy) 
			echo "Doing Password Policy"
			DO_PASSWORD_POLICY=TRUE 
			shift 
		;;
		--status) 
			DO_SHOW_STATUS=TRUE
			shift 
		;;
		--policy_document_path)
			shift
			POLICY_PATH=$1
			shift
			echo "Using $POLICY_PATH for my policy path"
		;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

# By (my) convention, all buckets are something.mydomain.tld to avoid namespace collisions with others. 
DOMAIN=$1
ACCOUNT_ID=$2
if [ -z "$ACCOUNT_ID" ] ; then
	usage
	exit 1
fi

if [ "$POLICY_PATH" == "" ] ; then
	POLICY_PATH="../policy_documents"
fi
if [ ! -d $POLICY_PATH ] ; then
	echo "Invald POLICY_PATH $POLICY_PATH"
	echo "I will be unable to help you much without that. Please specify a --policy_document_path"
	exit 1
fi

echo "Using $DOMAIN as my bucket suffix and $ACCOUNT_ID as my AWS Account Number"

# this needs global definition
LOG_BUCKET="logs.$DOMAIN"

# This will create the bucket that all the billing, cloudtrail and config service reports will dump into
create_logging_bucket() {
	# Create the log bucket if it doesn't already exit
	aws s3 ls s3://$LOG_BUCKET 2> /dev/null 1> /dev/null
	if [ $? -ne 0 ] ; then
		aws s3 mb s3://$LOG_BUCKET
	fi

	if [ ! -f ${POLICY_PATH}/cloud_trail_bucket_policy.json ] ; then
		echo "I can't find the cloud_trail_bucket_policy.json file in POLICY_PATH. Unable to proceed"
		exit 1
	fi

	sed s/MYBUCKET/$LOG_BUCKET/g ${POLICY_PATH}/cloud_trail_bucket_policy.json > /tmp/$LOG_BUCKET.cloudtrail_policy.json
	aws s3api get-bucket-policy --bucket $LOG_BUCKET 2> /dev/null > /tmp/$LOG_BUCKET.current_policy.json
	if [ $? -eq 0 ] ; then
		# This fugly diff will strip all the whitespace from both docs. Necessary because when I get-bucket-policy I don't get my original whitespace
		diff -w <(cat /tmp/$LOG_BUCKET.cloudtrail_policy.json | tr -d " \t\n\r" ) <(cat /tmp/$LOG_BUCKET.current_policy.json | tr -d " \t\n\r" ) >/dev/null
		if [ $? -ne 0 ] ; then
			# Update the policy
			echo "updating the bucket policy for $LOG_BUCKET"
			aws s3api put-bucket-policy --bucket $LOG_BUCKET --policy file:///tmp/$LOG_BUCKET.cloudtrail_policy.json
			if [ $? -ne 0 ] ; then
				echo "Error pushing bucket policy (/tmp/$LOG_BUCKET.cloudtrail_policy.json). Aborting"
				exit 1
			fi
		fi
	else
		# There was no policy, push it up there
		echo "Creating the bucket policy for $LOG_BUCKET"
		aws s3api put-bucket-policy --bucket $LOG_BUCKET --policy file:///tmp/$LOG_BUCKET.cloudtrail_policy.json
		if [ $? -ne 0 ] ; then
			echo "Error pushing bucket policy (/tmp/$LOG_BUCKET.cloudtrail_policy.json). Aborting"
			exit 1
		fi
	fi
} # end create_logging_bucket()

# This will setup a new bucket for all the detailed billing records to be dropped into.
do_detailed_billing() {
	# Lets make a bucket for dropping our detailed billing into
	create_logging_bucket
	echo "You must now visit this URL to enable \"Receive Billing Reports\": https://console.aws.amazon.com/billing/home#/preferences "
	echo "Your bucket for Billing reports is $LOG_BUCKET"
} # end do_detailed_billing()

# Create an Administrators Group. Make sure members of it are secure by requiring MFA in the last hour
do_create_admin_group() {
	if [ ! -f ${POLICY_PATH}/admin_require_mfa.json ] ; then
		echo "I'm having trouble finding the policy documents from the github checkout."
		exit 1
	fi
	# Create the group if it doesn't already exist
	aws iam get-group --group-name Administrators > /dev/null 2>&1 || aws iam create-group --group-name Administrators 

	# This will never overwrite, which is not ideal, but better than failing....
	# TODO: Maybe use policy versions???
	aws iam get-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/RequireMFAForAdmins > /dev/null 2>&1 ||
	aws iam create-policy --policy-name RequireMFAForAdmins --policy-document file://${POLICY_PATH}/admin_require_mfa.json

	# This command is idempotent
	aws iam attach-group-policy --group-name Administrators --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/RequireMFAForAdmins
} # end do_create_admin_group

# Lets turn on Cloud Trail in all regions. 
do_setup_cloudtrail() {
	create_logging_bucket

	echo "Creating our Chemtrails, err I mean Cloud Trails"
	# We don't need to record the global service events in all regions. Just do it in our default region
	for region in $REGIONS ; do 

		# Is there a trail already?
		C=`aws cloudtrail describe-trails --trail-name Default --output=text | wc -l`
		if [ $C -eq 0 ] ; then
			# We need to create the trail
			ACTION="create-trail"
			echo -n "Creating trail in $region...."
		else
			ACTION="update-trail"
			echo -n "Updating trail in $region...."
		fi

		# We only want the global events recorded once, in our default region
		if [ "$region" == "$AWS_DEFAULT_REGION" ] ; then
			EVENT="--include-global-service-events"
		else
			EVENT="--no-include-global-service-events"
		fi

		aws cloudtrail $ACTION --name Default --region=$region --s3-bucket-name $LOG_BUCKET $EVENT > /dev/null 2>&1
		if [ $? -ne 0 ] ; then
			echo "ERROR: Unable to create trail in $region. Skipping"
		else
			echo -n "Starting logger...."
			aws cloudtrail start-logging --region=$region --name Default
			if [ $? -eq 0 ] ; then
				echo "Done!"
			else
				echo "Error. Didn't start."
			fi
		fi

	done
	show_cloudtrail_status
} # end do_setup_cloudtrail

# AWS Config Service tracks state-change of resources. 
do_setup_configservice () {
	# Now we do Config Service
	# Create the configservice policy, give it write to the log bucket
	# Create a role with that policy
	# Create subscriptions in all regions
	# start logging in all regions

	# Make sure we have the bucket ready. 
	create_logging_bucket

	if [ ! -f ${POLICY_PATH}/config_assume_role.json ] || [ ! -f ${POLICY_PATH}/aws_config_service.TEMPLATE.json ] ; then
		echo "unable to find the aws config service managed policy template in $POLICY_PATH. Unable to proceed"
		return 1
	fi

	aws iam get-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/ConfigServicePolicy --output=text > /dev/null 2>/dev/null
	if [ $? -ne 0 ] ; then
		sed s/MYBUCKET/$LOG_BUCKET/g ${POLICY_PATH}/aws_config_service.TEMPLATE.json > /tmp/aws_config_service.json
		aws iam create-policy --policy-name ConfigServicePolicy --policy-document file:///tmp/aws_config_service.json
	fi

	aws iam get-role --role-name ConfigServiceRole 2> /dev/null >/dev/null
	if [ $? -ne 0 ] ; then 
		aws iam create-role --role-name ConfigServiceRole  --assume-role-policy-document file://${POLICY_PATH}/config_assume_role.json &&
		aws iam attach-role-policy --role-name ConfigServiceRole --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/ConfigServicePolicy
		if [ $? -ne 0 ] ; then
			echo "Problem creating the policy or role for AWS Config Service. Unable to do this step"
			return 1
		fi
	fi

	for region in $REGIONS ; do 
		echo -n "Setting up AWS Config Service in $region...."

		# AWS will barf if you've got an existing recorder as you can have only one per region. Here I get the name of the existing recorder
		# and reuse if if necessary. Otherwise, I go with Default-$region
		NAME=`aws configservice describe-configuration-recorders --output=text --region=$region --query 'ConfigurationRecorders[*].{name:name}'` 
		if [ "$NAME" == "" ] ; then
			NAME="Default-$region"
		fi
		echo -n " as $NAME.... "

		# We can only have one delivery channel
		CHANNEL_NAME=`aws configservice describe-delivery-channels --output=text --region=$region --query 'DeliveryChannels[*].{name:name}'` 
		if [ "$CHANNEL_NAME" == "" ] ; then
			CHANNEL_NAME="Default-$region"
		fi
		
		# Update or create the recorder using my ConfigServiceRole.
		# Point the recorder to the LOG Bucket, and then turn it all on. 
		aws configservice put-configuration-recorder --region=$region --configuration-recorder name=$NAME,roleARN=arn:aws:iam::$ACCOUNT_ID:role/ConfigServiceRole &&
		aws configservice put-delivery-channel --region=$region --delivery-channel name=$CHANNEL_NAME,s3BucketName=$LOG_BUCKET &&
		aws configservice start-configuration-recorder --region=$region --configuration-recorder-name $NAME
		if [ $? -ne 0 ] ; then
			echo
			echo "ERROR: Failed to create, update or start the configservice in $region. Aborting...."
			return 1
		fi
		echo "Done!"
	done
	echo
	show_configservice_status
} # end do_setup_configservice()

do_password_policy () {
	cat <<- EOP > /tmp/password_skel.json
	{
	    "AllowUsersToChangePassword": true,
	    "RequireLowercaseCharacters": true,
	    "RequireUppercaseCharacters": true,
	    "MinimumPasswordLength": 8,
	    "RequireNumbers": true,
	    "HardExpiry": false,
	    "RequireSymbols": true,
	    "MaxPasswordAge": 180
	}
	EOP
	aws iam update-account-password-policy --cli-input-json file:///tmp/password_skel.json
	if [ $? -eq 0 ] ; then
		echo "Account Password Policy Set"
		rm /tmp/password_skel.json
	else
		echo "Error setting password policy. Problem might be in /tmp/password_skel.json"
	fi
	aws iam get-account-password-policy --output=table
} # end do_password_policy

show_status () {
	show_cloudtrail_status
	show_configservice_status
	aws iam get-account-password-policy --output=table
} # end show_status()

show_cloudtrail_status() {
	echo "						Cloud Trail Status"
	echo "Region 		Trail Name 		Bucket 		GlobalEvents?		Logging On?"
	for region in $REGIONS ; do 
		LINE=`aws cloudtrail describe-trails --output=text --region=$region 2> /dev/null`
		NAME=`echo $LINE | awk '{print $4}'`
		BUCKET=`echo $LINE | awk '{print $5}'`
		GLOBAL=`echo $LINE | awk '{print $2}'`
		if [ ! -z "$NAME" ] ; then
			IS_LOGGING=`aws cloudtrail get-trail-status --output=text --name $NAME --region=$region 2> /dev/null | awk '{print $1}'`
			echo "$region 	$NAME 	$BUCKET 		$GLOBAL 		$IS_LOGGING"
		else
			echo "$region has no cloudtrail configured"
		fi
	done
	echo
} # end show_cloudtrail_status()

#--query 'ConfigurationRecordersStatus[*].{recording:recording,lastStatus:lastStatus,name:name}'

show_configservice_status() {
	echo "					AWS Config Service Status"
	echo "Region 		Recorder Name 		Bucket 			Last Status?		Recording?"
	for region in $REGIONS ; do 
		LINE=`aws configservice describe-configuration-recorder-status --output=text --region=$region --query 'ConfigurationRecordersStatus[*].{recording:recording,lastStatus:lastStatus,name:name}'`
		NAME=`echo $LINE | awk '{print $2}'`
		RECORDING=`echo $LINE | awk '{print $3}'`
		STATUS=`echo $LINE | awk '{print $1}'`
		BUCKET=`aws configservice describe-delivery-channels --output=text --region=$region | awk '{print $3}'`
		echo "$region 	$NAME 	$BUCKET 		$STATUS 		$RECORDING"
	done
	echo
} # end show_cloudtrail_status()


# If do All is set then execute in this order and quit. 
if [ "$DO_ALL" == "TRUE" ] ; then
	do_detailed_billing
	do_create_admin_group
	do_setup_cloudtrail
	do_setup_configservice
	do_password_policy
	exit 0
fi

if [ "$DO_SHOW_STATUS" == "TRUE" ] ; then
	show_status	
	# exit 0
fi

# Execute the steps in this order.
if [ "$DO_DETAILED_BILLING" == "TRUE" ] ; then
	do_detailed_billing
fi
if [ "$DO_CREATE_ADMIN_GROUP" == "TRUE" ] ; then
	do_create_admin_group
fi
if [ "$DO_SETUP_CLOUDTRAIL" == "TRUE" ] ; then
	do_setup_cloudtrail
fi
if [ "$DO_SETUP_CONFIGSERVICE" == "TRUE" ] ; then
	do_setup_configservice
fi
if [ "$DO_PASSWORD_POLICY" == "TRUE" ] ; then
	do_password_policy
fi


exit 0