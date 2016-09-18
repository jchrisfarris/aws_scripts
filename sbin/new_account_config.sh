#!/bin/bash
# This shell script will run a bunch of commands to prep a new AWS Account
# Hat Tip to Alex Tomic for the list of things to do here. 


# This is the Config & CloudTrail StackName
CloudTrail_STACK_NAME="ConfigCloudTrailSetup"
pTagApplication="aws-admin"



# TODO - Make this whole thing getopts. For now its uncomment the parts you want to run. 
usage() {
	echo "Usage: $0 <log-bucket> <aws_account_number> <your_email>"
	echo "Options:"
	echo "	--all - Execute all the steps"
	echo "	--password_policy - do this thing"
	echo "	--create_admin_group - do this thing"
	echo "	--setup_cloudtrail - do this thing"

	echo "	--status - Show the status of the things this script will setup."
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
		--password_policy) 
			echo "Doing Password Policy"
			DO_PASSWORD_POLICY=TRUE 
			shift 
		;;
		--region) 
			shift
			REGIONS=$1
			shift 
			echo "Only Doing Region: $REGIONS"
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

do_password_policy () {
	aws iam update-account-password-policy --cli-input-json file://${POLICY_PATH}/account-password-policy.json
	if [ $? -eq 0 ] ; then
		echo "Account Password Policy Set"
	else
		echo "Error setting password policy. Problem might be in ${POLICY_PATH}/account-password-policy.json"
		exit 1
	fi
	aws iam get-account-password-policy --output=table
} # end do_password_policy

show_status () {
	show_cloudtrail_status
	# show_configservice_status
	aws iam get-account-password-policy --output=table
} # end show_status()

show_cloudtrail_status() {
	echo "						Cloud Trail Status"
	aws cloudtrail describe-trails --output=table --query 'trailList[*].{IncludeGlobalServiceEvents:IncludeGlobalServiceEvents,IsMultiRegionTrail:IsMultiRegionTrail,S3BucketName:S3BucketName,HomeRegion:HomeRegion}'
	echo "IncludeGlobalServiceEvents and IsMultiRegionTrail should both be true"
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

do_deploy_config_and_cloudtrail_stack() {

	TEMPLATE="$BASE_PATH/admin_cloudformation_stacks/ConfigCloudTrail.cform"
	if [ ! -f $TEMPLATE ] ; then
		echo "Cannot find $TEMPLATE"
		exit 1
	fi

	# See if my logging bucket exists already
	aws s3api list-buckets --output=text |awk '{print $NF}' | grep ^$LOG_BUCKET$ >/dev/null
	if [ $? -eq 0 ] ; then
		pCreateBucket="false"
		echo "Reusing Existing Bucket"
	else
		pCreateBucket="true"
	fi

	# decide if I'm creating or updating the stack
	aws cloudformation describe-stacks --stack-name $CloudTrail_STACK_NAME > /dev/null 2>&1
	if [ $? -eq 0 ] ; then # Stack Exists
		ACTION="update-stack"
	else
		# Create the stack
		ACTION="create-stack"
	fi

	echo "Deploying $CloudTrail_STACK_NAME to create CloudTrail & ConfigService "
	aws cloudformation $ACTION --stack-name $CloudTrail_STACK_NAME --template-body file://$TEMPLATE \
		--parameters ParameterKey=pLoggingBucketName,ParameterValue=$LOG_BUCKET,UsePreviousValue=false \
				ParameterKey=pOperatorEmail,ParameterValue=$EMAIL,UsePreviousValue=false \
				ParameterKey=pTagApplication,ParameterValue=$pTagApplication,UsePreviousValue=false \
				ParameterKey=pTagCreatedBy,ParameterValue=$EMAIL,UsePreviousValue=false \
				ParameterKey=pCreateBucket,ParameterValue=$pCreateBucket,UsePreviousValue=false \
		--tags Key=Name,Value=$CloudTrail_STACK_NAME Key=creator,Value=$EMAIL \
		--capabilities CAPABILITY_NAMED_IAM --output text

} # end do_deploy_config_and_cloudtrail_stack


##############################################################################
# End of functions
##############################################################################

# Don't validate Params on just a status check
if [ "$DO_SHOW_STATUS" == "TRUE" ] ; then
	show_status	
	exit 0
fi


# These are passed in as args
LOG_BUCKET=$1
ACCOUNT_ID=$2
EMAIL=$3
if [ -z "$EMAIL" ] ; then
	usage
	exit 1
fi

# figure out where we are and the relative path to helper scripts
MY_PATH=`dirname $0`
if [ $MY_PATH == "." ] ; then
	BASE_PATH=".."
else
	BASE_PATH=`dirname $MY_PATH`
fi

if [ "$POLICY_PATH" == "" ] ; then
	POLICY_PATH="$BASE_PATH/policy_documents"
fi
if [ ! -d $POLICY_PATH ] ; then
	echo "Invald POLICY_PATH $POLICY_PATH"
	exit 1
fi

echo "Using $LOG_BUCKET as my log bucket and $ACCOUNT_ID as my AWS Account Number"

# If do All is set then execute in this order and quit. 
if [ "$DO_ALL" == "TRUE" ] ; then
	do_create_admin_group
	do_deploy_config_and_cloudtrail_stack
	do_password_policy
	exit 0
fi

# Otherwise Execute the steps in this order.
if [ "$DO_CREATE_ADMIN_GROUP" == "TRUE" ] ; then
	do_create_admin_group
fi
if [ "$DO_SETUP_CLOUDTRAIL" == "TRUE" ] ; then
	do_deploy_config_and_cloudtrail_stack
fi
if [ "$DO_PASSWORD_POLICY" == "TRUE" ] ; then
	do_password_policy
fi

exit 0