#!/bin/bash
# This shell script will run a bunch of commands to prep a new AWS Account
# Hat Tip to Alex Tomic for the list of things to do here. 

# By (my) convention, all buckets are something.mydomain.tld to avoid namespace collisions with others. 
DOMAIN=$1
ACCOUNT_ID=$2

if [ -z "$ACCOUNT_ID" ] ; then
	echo "Check the usage"
	exit 1
fi

REGIONS=`aws ec2 describe-regions --output=text | awk '{print $NF}'`

# TODO - Make this whole thing getopts. For now its uncomment the parts you want to run. 



# This will setup a new bucket for all the detailed billing records to be dropped into.
do_detailed_billing() {
	# Lets make a bucket for dropping our detailed billing into
	BILLING_BUCKET="billing.$DOMAIN"
	aws s3 mb s3://$BILLING_BUCKET

	# Here is the policy to apply to that bucket
	cat <<- EOP > /tmp/billing_bucket_policy.json
	{
	  "Version": "2008-10-17",
	  "Id": "Policy1335892530063",
	  "Statement": [
	    {
	      "Sid": "Stmt1335892150622",
	      "Effect": "Allow",
	      "Principal": {
	        "AWS": "arn:aws:iam::386209384616:root"
	      },
	      "Action": [
	        "s3:GetBucketAcl",
	        "s3:GetBucketPolicy"
	      ],
	      "Resource": "arn:aws:s3:::$BILLING_BUCKET"
	    },
	    {
	      "Sid": "Stmt1335892526596",
	      "Effect": "Allow",
	      "Principal": {
	        "AWS": "arn:aws:iam::386209384616:root"
	      },
	      "Action": [
	        "s3:PutObject"
	      ],
	      "Resource": "arn:aws:s3:::$BILLING_BUCKET/*"
	    }
	  ]
	}
	EOP
	aws s3api put-bucket-policy --bucket $BILLING_BUCKET --policy file:///tmp/billing_bucket_policy.json

	echo "You must now visit this URL to enable \"Receive Billing Reports\": https://console.aws.amazon.com/billing/home#/preferences "
	echo "Your bucket for Billing reports is $BILLING_BUCKET"
} # end do_detailed_billing()

# Create an Administrators Group. Make sure members of it are secure
do_create_admin_group() {
	aws iam create-group --group-name Administrators 
	aws iam create-policy --policy-name RequireMFAForAdmins --policy-document file://policy_documents/admin_require_mfa.json
	aws iam attach-group-policy --group-name Administrators --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/RequireMFAForAdmins
} # end do_create_admin_group

# Lets turn on Cloud Trail in all regions. 
do_setup_cloudtrail() {
	# Create the log bucket if it doesn't already exit
	LOG_BUCKET="logs.$DOMAIN"
	aws s3 mb s3://$LOG_BUCKET

	# We don't need to record the global service events in all regions. Just do it in our default region
	for region in $REGIONS ; do 
		if [ "$region" == "$AWS_DEFAULT_REGION" ] ; then
			aws cloudtrail create-trail --name Default --region=$region --s3-bucket-name $LOG_BUCKET --include-global-service-events
		else
			aws cloudtrail create-trail --name Default --region=$region --s3-bucket-name $LOG_BUCKET --no-include-global-service-events
		fi
		aws cloudtrail start-logging --region=$region --name Default 
	done
} # end do_setup_cloudtrail

# AWS Config Service tracks state-change of resources. 
do_setup_configservice () {
	# Now we do Config Service
	# Create the configservice policy, give it write to the log bucket
	# Create a role with that policy
	# Create subscriptions in all regions
	# start logging in all regions
	cat <<- EOP > /tmp/configservice_policy.json
	{
	  "Version": "2012-10-17",
	  "Statement": [
	    {
	      "Action": [
	        "appstream:Get*",
	        "autoscaling:Describe*",
	        "cloudformation:DescribeStacks",
	        "cloudformation:DescribeStackEvents",
	        "cloudformation:DescribeStackResource",
	        "cloudformation:DescribeStackResources",
	        "cloudformation:GetTemplate",
	        "cloudformation:List*",
	        "cloudfront:Get*",
	        "cloudfront:List*",
	        "cloudtrail:DescribeTrails",
	        "cloudtrail:GetTrailStatus",
	        "cloudwatch:Describe*",
	        "cloudwatch:Get*",
	        "cloudwatch:List*",
	        "config:Put*",
	        "directconnect:Describe*",
	        "dynamodb:GetItem",
	        "dynamodb:BatchGetItem",
	        "dynamodb:Query",
	        "dynamodb:Scan",
	        "dynamodb:DescribeTable",
	        "dynamodb:ListTables",
	        "ec2:Describe*",
	        "elasticache:Describe*",
	        "elasticbeanstalk:Check*",
	        "elasticbeanstalk:Describe*",
	        "elasticbeanstalk:List*",
	        "elasticbeanstalk:RequestEnvironmentInfo",
	        "elasticbeanstalk:RetrieveEnvironmentInfo",
	        "elasticloadbalancing:Describe*",
	        "elastictranscoder:Read*",
	        "elastictranscoder:List*",
	        "iam:List*",
	        "iam:Get*",
	        "kinesis:Describe*",
	        "kinesis:Get*",
	        "kinesis:List*",
	        "opsworks:Describe*",
	        "opsworks:Get*",
	        "route53:Get*",
	        "route53:List*",
	        "redshift:Describe*",
	        "redshift:ViewQueriesInConsole",
	        "rds:Describe*",
	        "rds:ListTagsForResource",
	        "s3:Get*",
	        "s3:List*",
	        "sdb:GetAttributes",
	        "sdb:List*",
	        "sdb:Select*",
	        "ses:Get*",
	        "ses:List*",
	        "sns:Get*",
	        "sns:List*",
	        "sqs:GetQueueAttributes",
	        "sqs:ListQueues",
	        "sqs:ReceiveMessage",
	        "storagegateway:List*",
	        "storagegateway:Describe*",
	        "trustedadvisor:Describe*"
	      ],
	      "Effect": "Allow",
	      "Resource": "*"
	    },
	    {
	      "Effect": "Allow",
	      "Action": [
	        "s3:PutObject*"
	      ],
	      "Resource": [
	        "arn:aws:s3:::$LOG_BUCKET/AWSLogs/$ACCOUNT_ID/*"
	      ],
	      "Condition": {
	        "StringLike": {
	          "s3:x-amz-acl": "bucket-owner-full-control"
	        }
	      }
	    },
	    {
	      "Effect": "Allow",
	      "Action": [
	        "s3:GetBucketAcl"
	      ],
	      "Resource": "arn:aws:s3:::$LOG_BUCKET"
	    }
	  ]
	}
	EOP
	aws iam create-policy --policy-name ConfigServicePolicy --policy-document file:///tmp/configservice_policy.json
	aws iam create-role --role-name ConfigServiceRole  --assume-role-policy-document file://policy_documents/config_assume_role.json
	aws iam attach-role-policy --role-name ConfigServiceRole --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/ConfigServicePolicy

	for region in $REGIONS ; do 
		echo "Setting up AWS Config Service in $region"
		aws configservice put-configuration-recorder --region=$region --configuration-recorder name=Default-$region,roleARN=arn:aws:iam::$ACCOUNT_ID:role/ConfigServiceRole
		aws configservice put-delivery-channel --region=$region --delivery-channel name=Default-$region,s3BucketName=$LOG_BUCKET
		aws configservice start-configuration-recorder --region=$region --configuration-recorder-name Default-$region
	done
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
} # end do_password_policy

show_status () {

	aws iam get-account-password-policy --output=table
exit
	# Lets do some regional status stuff at the end
	for region in $REGIONS ; do 
		echo "Checking status of things in $region"
		aws cloudtrail describe-trails --output=table --region=$region
		aws cloudtrail get-trail-status --output=table --name Default --region=$region
		aws configservice get-status --region=$region
		aws configservice describe-delivery-channels --output=text
		echo "Press Any Key to Continue..."
		read
	done

}

# do_detailed_billing
# do_create_admin_group
# do_setup_cloudtrail
# do_setup_configservice
# do_password_policy
show_status