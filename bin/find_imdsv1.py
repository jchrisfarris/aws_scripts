#!/usr/bin/env python3

# Copyright 2025 Chris Farris <chris@primeharbor.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import boto3
import csv
import argparse
import logging
from botocore.exceptions import ClientError
from datetime import datetime, timedelta, timezone

# Set up logging
logging.basicConfig(level=logging.INFO)
logging.getLogger('botocore').setLevel(logging.WARNING)
logging.getLogger('boto3').setLevel(logging.WARNING)
logging.getLogger('urllib3').setLevel(logging.WARNING)
logger = logging.getLogger()


def assume_role(account_id, role_name, role_session_name):
    """Assume a role in a given AWS account."""
    sts_client = boto3.client('sts')
    try:
        assumed_role_object = sts_client.assume_role(
            RoleArn=f'arn:aws:iam::{account_id}:role/{role_name}',
            RoleSessionName=role_session_name
        )
        credentials = assumed_role_object['Credentials']
        logger.debug(f"Successfully assumed role in account {account_id}")
        return credentials
    except ClientError as e:
        logger.warning(f"Failed to assume role for account {account_id}: {e}")
        return None

def get_account_name(account_id):
    """Get the name of the AWS account using the Organizations service."""
    org_client = boto3.client('organizations')
    try:
        account = org_client.describe_account(AccountId=account_id)
        return account['Account']['Name']
    except ClientError as e:
        logger.warning(f"Failed to retrieve account name for account {account_id}: {e}")
        return 'N/A'

def get_all_regions(session):
    """Get all available AWS regions."""
    ec2_client = session.client('ec2')
    regions = ec2_client.describe_regions()['Regions']
    return [region['RegionName'] for region in regions]

def list_accounts():
    """Get all AWS account IDs in the organization."""
    org_client = boto3.client('organizations')
    accounts = []
    try:
        paginator = org_client.get_paginator('list_accounts')
        for page in paginator.paginate():
            accounts.extend([account['Id'] for account in page['Accounts']])
        logger.debug("Successfully fetched list of accounts.")
    except ClientError as e:
        logger.critical(f"Failed to list accounts in the organization: {e}")
        raise
    return accounts

def main():
    parser = argparse.ArgumentParser(description='Fetch EC2 instance and AMI details across all accounts in the organization.')
    parser.add_argument('--assume-role', required=True, help='The IAM Role to assume into each account')
    parser.add_argument('--role-session-name', default='imdsv1-usage-report', help='The RoleSession Name for assuming the role')
    parser.add_argument('--debug', action='store_true', help='Enable debug-level logging')
    args = parser.parse_args()

    # Set logging level based on --debug argument
    if args.debug:
        logger.setLevel(logging.DEBUG)
        logger.debug("Debug-level logging is enabled.")


    # Get all account IDs in the organization
    accounts = list_accounts()

    # Loop through each account and assume the role
    for account_id in accounts:
        credentials = assume_role(account_id, args.assume_role, args.role_session_name)
        if credentials is None:
            continue

        # Get the account name
        account_name = get_account_name(account_id)

        # Create a session with the assumed role credentials
        session = boto3.Session(
            aws_access_key_id=credentials['AccessKeyId'],
            aws_secret_access_key=credentials['SecretAccessKey'],
            aws_session_token=credentials['SessionToken']
        )

        # Get regions
        regions = get_all_regions(session)
        # regions=["us-east-1"]

        # Get EC2 instances in each region
        for region in regions:
            logger.debug(f"Processing region {region} for account {account_name} ({account_id})")
            try:
                count = get_last_week_metric_total(session, region)
                if count != 0:
                    print(f"{account_name}({account_id}) - {region}: {int(count)} IMDSv1 calls in the last week")
            except ClientError as e:
                logger.warning(f"Region {region} is blocked due to permissions: {e}")

def get_last_week_metric_total(session, region, namespace='AWS/EC2', metric_name='MetadataNoToken'):
    """
    Retrieves the total sum of the CloudWatch metric 'MetadataNoToken' for the last week.

    :param session: A valid boto3 session for the target AWS account and region.
    :param namespace: The CloudWatch namespace for the metric.
    :param metric_name: The name of the metric.
    :return: The total sum of the metric over the last week.
    """
    cloudwatch = session.client('cloudwatch', region_name=region)

    end_time = datetime.now(timezone.utc)
    start_time = end_time - timedelta(days=7)

    response = cloudwatch.get_metric_statistics(
        Namespace=namespace,
        MetricName=metric_name,
        StartTime=start_time,
        EndTime=end_time,
        Period=3600,  # 1 day in seconds
        Statistics=['Sum']
    )

    total = sum(dp['Sum'] for dp in response.get('Datapoints', []))
    return total


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        logger.critical(f"Fatal error: {e}")
        raise
