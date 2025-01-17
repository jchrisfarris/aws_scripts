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

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()

# Global AMI hash set to store AMI details (using AMI ID as the key)
ami_hash = {}

def assume_role(account_id, role_name, role_session_name):
    """Assume a role in a given AWS account."""
    sts_client = boto3.client('sts')
    try:
        assumed_role_object = sts_client.assume_role(
            RoleArn=f'arn:aws:iam::{account_id}:role/{role_name}',
            RoleSessionName=role_session_name
        )
        credentials = assumed_role_object['Credentials']
        logger.info(f"Successfully assumed role in account {account_id}")
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

def get_ec2_instances(region, session, account_id, account_name):
    """Get EC2 instances in a given region."""
    ec2_client = session.client('ec2', region_name=region)
    instances = []
    try:
        reservations = ec2_client.describe_instances()
        for reservation in reservations['Reservations']:
            for instance in reservation['Instances']:
                instance_data = {
                    'InstanceId': instance['InstanceId'],
                    'LaunchTime': instance['LaunchTime'],
                    'State': instance['State']['Name'],
                    'ImageId': instance['ImageId'],
                    'InstanceName': 'N/A',  # Default value for instance name
                    'AccountId': account_id,
                    'AccountName': account_name,
                    'Region': region
                }

                # Get instance name from tags
                for tag in instance.get('Tags', []):
                    if tag['Key'] == 'Name':
                        instance_data['InstanceName'] = tag['Value']

                ami_id = instance['ImageId']

                # Fetch AMI details if not already seen or if the AMI is missing
                if ami_id not in ami_hash:
                    try:
                        ami = ec2_client.describe_images(ImageIds=[ami_id])['Images'][0]
                        ami_hash[ami_id] = {
                            'AmiName': ami['Name'],
                            'AmiDescription': ami.get('Description', 'N/A'),
                            'AmiCreationDate': ami['CreationDate'],
                            'AmiOwner': ami['OwnerId'],
                            'AmiImageOwnerAlias': ami.get('ImageOwnerAlias', 'N/A'),
                            'AmiDeprecationTime': ami.get('DeprecationTime', 'N/A'),
                            'AmiImdsSupport': ami.get('ImdsSupport', 'N/A'),
                            'AmiLastLaunchedTime': ami.get('LastLaunchedTime', 'N/A'),
                            'AmiImageAllowed': ami.get('ImageAllowed', 'N/A'),
                            'AmiSourceImageId': ami.get('SourceImageId', 'N/A'),
                            'AmiState': ami.get('State', 'N/A'),
                            'AmiPublic': ami.get('Public', False)
                        }
                    except Exception as e:
                        # If the AMI is missing or any other exception occurs, set all AMI-related fields to "AMI MISSING"
                        logger.warning(f"Error retrieving AMI {ami_id} in region {region}: {e}")
                        ami_hash[ami_id] = {
                            'AmiName': 'AMI MISSING',
                            'AmiDescription': 'AMI MISSING',
                            'AmiCreationDate': 'AMI MISSING',
                            'AmiOwner': 'AMI MISSING',
                            'AmiImageOwnerAlias': 'AMI MISSING',
                            'AmiDeprecationTime': 'AMI MISSING',
                            'AmiImdsSupport': 'AMI MISSING',
                            'AmiLastLaunchedTime': 'AMI MISSING',
                            'AmiImageAllowed': 'AMI MISSING',
                            'AmiSourceImageId': 'AMI MISSING',
                            'AmiState': 'AMI MISSING',
                            'AmiPublic': 'AMI MISSING'
                        }
                # Use the stored AMI details from the hash
                instance_data.update(ami_hash[ami_id])
                instances.append(instance_data)
    except ClientError as e:
        logger.warning(f"Failed to retrieve EC2 instances in region {region}: {e}")
    return instances

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
        logger.info("Successfully fetched list of accounts.")
    except ClientError as e:
        logger.critical(f"Failed to list accounts in the organization: {e}")
        raise
    return accounts

def write_csv(outfile, data):
    """Write the EC2 instance data to a CSV file."""
    fieldnames = [
        'AccountId', 'AccountName', 'Region', 'InstanceId', 'LaunchTime', 'State', 'ImageId', 'InstanceName',
        'AmiName', 'AmiDescription', 'AmiCreationDate', 'AmiOwner', 'AmiImageOwnerAlias', 'AmiDeprecationTime',
        'AmiImdsSupport', 'AmiLastLaunchedTime', 'AmiImageAllowed', 'AmiSourceImageId', 'AmiState', 'AmiPublic'
    ]
    with open(outfile, mode='w', newline='') as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(data)
    logger.info(f"CSV report written to {outfile}")

def main():
    parser = argparse.ArgumentParser(description='Fetch EC2 instance and AMI details across all accounts in the organization.')
    parser.add_argument('--assume-role', required=True, help='The IAM Role to assume into each account')
    parser.add_argument('--role-session-name', default='ec2_instance_ami_report', help='The RoleSession Name for assuming the role')
    parser.add_argument('--outfile', default='ec2_instance_report.csv', help='The output CSV file name')
    args = parser.parse_args()

    # Get all account IDs in the organization
    accounts = list_accounts()

    all_instances = []

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

        # Get EC2 instances in each region
        for region in regions:
            logger.info(f"Processing region {region} for account {account_id}")
            try:
                instances = get_ec2_instances(region, session, account_id, account_name)
                all_instances.extend(instances)
            except ClientError as e:
                logger.warning(f"Region {region} is blocked due to permissions: {e}")

    # Write results to CSV
    write_csv(args.outfile, all_instances)

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        logger.critical(f"Fatal error: {e}")
        raise
