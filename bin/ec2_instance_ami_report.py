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
import re
import json
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

def detect_os_version(ami_name):
    """
    Detect OS version from AMI name using regex pattern matching.
    Returns a human-readable OS version string or 'Unknown'.
    """
    if not ami_name or ami_name in ['N/A', 'AMI MISSING', 'SOURCE AMI MISSING']:
        return 'Unknown'

    # Amazon Linux 2023 (EKS)
    if re.match(r'^amazon-eks-node-al2023-', ami_name):
        return 'Amazon Linux 2023 (EKS)'

    # Amazon Linux 2023
    if re.match(r'^al2023-ami-2023\.\d+\.', ami_name):
        return 'Amazon Linux 2023'

    # Amazon Linux 2 (various types: standard, ECS, kernel 5.10)
    if re.match(r'^amzn2-ami-.*-2\.0\.', ami_name):
        if 'ecs' in ami_name.lower():
            return 'Amazon Linux 2 (ECS)'
        elif 'kernel-5.10' in ami_name:
            return 'Amazon Linux 2 (Kernel 5.10)'
        return 'Amazon Linux 2'

    # Amazon Linux 1 (Legacy)
    if re.match(r'^amzn-ami-hvm-201[7-9]\.', ami_name):
        return 'Amazon Linux'

    # Ubuntu with version detection
    ubuntu_match = re.search(r'ubuntu-(bionic|focal|jammy|noble)-(\d+\.\d+)', ami_name)
    if ubuntu_match:
        codename = ubuntu_match.group(1)
        version = ubuntu_match.group(2)
        return f'Ubuntu {version} LTS'

    # Ubuntu without explicit version (use codename mapping)
    if 'ubuntu' in ami_name.lower():
        if 'bionic' in ami_name:
            return 'Ubuntu 18.04 LTS'
        elif 'focal' in ami_name:
            return 'Ubuntu 20.04 LTS'
        elif 'jammy' in ami_name:
            return 'Ubuntu 22.04 LTS'
        elif 'noble' in ami_name:
            return 'Ubuntu 24.04 LTS'
        return 'Ubuntu'

    # Windows Server
    windows_match = re.search(r'[Ww]indows\s+(\d{4})', ami_name)
    if windows_match:
        year = windows_match.group(1)
        return f'Windows Server {year}'

    # Windows with hyphenated format
    windows_dash_match = re.match(r'^windows-(\d{4})-', ami_name)
    if windows_dash_match:
        year = windows_dash_match.group(1)
        return f'Windows Server {year}'

    # Elastic Beanstalk
    if re.match(r'^aws-elasticbeanstalk-amzn-', ami_name):
        if '2.0' in ami_name:
            return 'Amazon Linux 2 (Elastic Beanstalk)'
        return 'Amazon Linux (Elastic Beanstalk)'

    # Default to Unknown for custom/unrecognized AMIs
    return 'Unknown'

def get_ancestor_ami(ec2_client, ami_id, region):
    """
    Get the root ancestor AMI using the get_image_ancestry API.
    Returns tuple of (ancestor_ami_id, ancestor_ami_name) or ('N/A', 'N/A') if not found.
    """
    if ami_id in ['N/A', 'AMI MISSING']:
        return ('N/A', 'N/A')

    try:
        # Use the new get_image_ancestry API
        response = ec2_client.get_image_ancestry(ImageId=ami_id)

        # The ancestry is returned in chronological order (oldest to newest)
        # The first item is the root ancestor
        if 'Ancestors' in response and len(response['Ancestors']) > 0:
            # Get the root ancestor (first in the list)
            root_ancestor = response['Ancestors'][0]
            ancestor_id = root_ancestor['ImageId']
            ancestor_name = root_ancestor.get('Name', 'N/A')

            logger.info(f"Found ancestor for {ami_id}: {ancestor_id} ({ancestor_name})")
            return (ancestor_id, ancestor_name)
        else:
            # No ancestors found - this AMI is the root itself
            if ami_id in ami_hash:
                ami_name = ami_hash[ami_id].get('AmiName', 'N/A')
                return (ami_id, ami_name)

            # Try to get the name from API
            try:
                ami = ec2_client.describe_images(ImageIds=[ami_id])['Images'][0]
                return (ami_id, ami['Name'])
            except Exception as e:
                logger.warning(f"Could not get AMI details for {ami_id}: {e}")
                return (ami_id, 'N/A')

    except ClientError as e:
        # Handle case where get_image_ancestry is not supported or AMI not found
        error_code = e.response.get('Error', {}).get('Code', '')
        if error_code == 'InvalidAMIID.NotFound':
            logger.warning(f"AMI {ami_id} not found")
            return ('N/A', 'N/A')
        elif error_code == 'InvalidParameterValue':
            logger.warning(f"Invalid AMI ID format: {ami_id}")
            return ('N/A', 'N/A')
        else:
            logger.warning(f"Error getting ancestry for AMI {ami_id}: {e}")
            return ('N/A', 'N/A')
    except Exception as e:
        logger.warning(f"Unexpected error tracing ancestry for AMI {ami_id}: {e}")
        return ('N/A', 'N/A')

def get_ec2_instances(region, session, account_id, account_name):
    """Get EC2 instances in a given region."""
    ec2_client = session.client('ec2', region_name=region)
    instances = []
    try:
        reservations = ec2_client.describe_instances()
        for reservation in reservations['Reservations']:
            for instance in reservation['Instances']:
                # Extract StateTransitionTime from StateTransitionReason
                state_transition_reason = instance.get('StateTransitionReason', 'N/A')
                state_transition_time = 'N/A'
                if state_transition_reason != 'N/A':
                    # Try to extract date from format like "User initiated (2025-08-05 00:15:30 GMT)"
                    match = re.search(r'\((\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', state_transition_reason)
                    if match:
                        state_transition_time = match.group(1)

                # Calculate total disk size from all volumes
                disk_size_gb = 0
                for block_device in instance.get('BlockDeviceMappings', []):
                    if 'Ebs' in block_device:
                        volume_id = block_device['Ebs']['VolumeId']
                        try:
                            volume = ec2_client.describe_volumes(VolumeIds=[volume_id])['Volumes'][0]
                            disk_size_gb += volume['Size']
                        except Exception as e:
                            logger.warning(f"Failed to get volume {volume_id} size: {e}")

                # Extract IAM role name from IamInstanceProfile ARN
                iam_role = 'N/A'
                if 'IamInstanceProfile' in instance:
                    iam_arn = instance['IamInstanceProfile'].get('Arn', '')
                    # ARN format: arn:aws:iam::123456789012:instance-profile/RoleName
                    if iam_arn:
                        iam_role = iam_arn.split('/')[-1]

                instance_data = {
                    'InstanceId': instance['InstanceId'],
                    'LaunchTime': instance['LaunchTime'],
                    'State': instance['State']['Name'],
                    'StateTransitionReason': state_transition_reason,
                    'StateTransitionTime': state_transition_time,
                    'ImageId': instance['ImageId'],
                    'InstanceName': 'N/A',  # Default value for instance name
                    'AccountId': account_id,
                    'AccountName': account_name,
                    'Region': region,
                    'PublicIPAddress': instance.get('PublicIpAddress', 'N/A'),
                    'KeyName': instance.get('KeyName', 'N/A'),
                    'PlatformDetails': instance.get('PlatformDetails', 'N/A'),
                    'HttpTokens': instance.get('MetadataOptions', {}).get('HttpTokens', 'N/A'),
                    'IAMRole': iam_role,
                    'DiskSizeGB': disk_size_gb
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
                        source_image_id = ami.get('SourceImageId', 'N/A')
                        ami_name = ami['Name']
                        ami_hash[ami_id] = {
                            'AmiName': ami_name,
                            'OSVersion': detect_os_version(ami_name),
                            'AmiDescription': ami.get('Description', 'N/A'),
                            'AmiCreationDate': ami['CreationDate'],
                            'AmiOwner': ami['OwnerId'],
                            'AmiImageOwnerAlias': ami.get('ImageOwnerAlias', 'N/A'),
                            'AmiDeprecationTime': ami.get('DeprecationTime', 'N/A'),
                            'AmiImdsSupport': ami.get('ImdsSupport', 'N/A'),
                            'AmiLastLaunchedTime': ami.get('LastLaunchedTime', 'N/A'),
                            'AmiImageAllowed': ami.get('ImageAllowed', 'N/A'),
                            'AmiSourceImageId': source_image_id,
                            'AmiSourceName': 'N/A',
                            'AmiState': ami.get('State', 'N/A'),
                            'AmiPublic': ami.get('Public', False),
                            'AncestorAmiId': 'N/A',
                            'AncestorAmiName': 'N/A',
                            'AncestorOSVersion': 'Unknown'
                        }

                        # Trace back to the ancestor AMI
                        ancestor_id, ancestor_name = get_ancestor_ami(ec2_client, ami_id, region)
                        ami_hash[ami_id]['AncestorAmiId'] = ancestor_id
                        ami_hash[ami_id]['AncestorAmiName'] = ancestor_name
                        ami_hash[ami_id]['AncestorOSVersion'] = detect_os_version(ancestor_name)

                        # Lookup the source AMI if it exists
                        if source_image_id != 'N/A' and source_image_id not in ami_hash:
                            try:
                                source_ami = ec2_client.describe_images(ImageIds=[source_image_id])['Images'][0]
                                source_ami_name = source_ami['Name']
                                ami_hash[source_image_id] = {
                                    'AmiName': source_ami_name,
                                    'OSVersion': detect_os_version(source_ami_name),
                                    'AmiDescription': source_ami.get('Description', 'N/A'),
                                    'AmiCreationDate': source_ami['CreationDate'],
                                    'AmiOwner': source_ami['OwnerId'],
                                    'AmiImageOwnerAlias': source_ami.get('ImageOwnerAlias', 'N/A'),
                                    'AmiDeprecationTime': source_ami.get('DeprecationTime', 'N/A'),
                                    'AmiImdsSupport': source_ami.get('ImdsSupport', 'N/A'),
                                    'AmiLastLaunchedTime': source_ami.get('LastLaunchedTime', 'N/A'),
                                    'AmiImageAllowed': source_ami.get('ImageAllowed', 'N/A'),
                                    'AmiSourceImageId': source_ami.get('SourceImageId', 'N/A'),
                                    'AmiSourceName': 'N/A',
                                    'AmiState': source_ami.get('State', 'N/A'),
                                    'AmiPublic': source_ami.get('Public', False),
                                    'AncestorAmiId': 'N/A',
                                    'AncestorAmiName': 'N/A',
                                    'AncestorOSVersion': 'Unknown'
                                }
                                ami_hash[ami_id]['AmiSourceName'] = source_ami_name

                                # Trace ancestor for source AMI too
                                src_ancestor_id, src_ancestor_name = get_ancestor_ami(ec2_client, source_image_id, region)
                                ami_hash[source_image_id]['AncestorAmiId'] = src_ancestor_id
                                ami_hash[source_image_id]['AncestorAmiName'] = src_ancestor_name
                                ami_hash[source_image_id]['AncestorOSVersion'] = detect_os_version(src_ancestor_name)
                            except Exception as e:
                                logger.warning(f"Error retrieving source AMI {source_image_id} in region {region}: {e}")
                                ami_hash[ami_id]['AmiSourceName'] = 'SOURCE AMI MISSING'
                        elif source_image_id in ami_hash:
                            ami_hash[ami_id]['AmiSourceName'] = ami_hash[source_image_id]['AmiName']

                    except Exception as e:
                        # If the AMI is missing or any other exception occurs, set all AMI-related fields to "AMI MISSING"
                        logger.warning(f"Error retrieving AMI {ami_id} in region {region}: {e}")
                        ami_hash[ami_id] = {
                            'AmiName': 'AMI MISSING',
                            'OSVersion': 'Unknown',
                            'AmiDescription': 'AMI MISSING',
                            'AmiCreationDate': 'AMI MISSING',
                            'AmiOwner': 'AMI MISSING',
                            'AmiImageOwnerAlias': 'AMI MISSING',
                            'AmiDeprecationTime': 'AMI MISSING',
                            'AmiImdsSupport': 'AMI MISSING',
                            'AmiLastLaunchedTime': 'AMI MISSING',
                            'AmiImageAllowed': 'AMI MISSING',
                            'AmiSourceImageId': 'AMI MISSING',
                            'AmiSourceName': 'AMI MISSING',
                            'AmiState': 'AMI MISSING',
                            'AmiPublic': 'AMI MISSING',
                            'AncestorAmiId': 'N/A',
                            'AncestorAmiName': 'N/A',
                            'AncestorOSVersion': 'Unknown'
                        }
                        pass
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

def load_ami_cache(filename):
    """Load the AMI hash from a JSON file."""
    global ami_hash
    try:
        with open(filename, 'r') as f:
            ami_hash = json.load(f)
        logger.info(f"Loaded {len(ami_hash)} AMI entries from {filename}")
    except FileNotFoundError:
        logger.warning(f"AMI cache file {filename} not found, starting with empty cache")
    except Exception as e:
        logger.error(f"Error loading AMI cache from {filename}: {e}")

def dump_ami_cache(filename):
    """Dump the AMI hash to a JSON file."""
    try:
        with open(filename, 'w') as f:
            json.dump(ami_hash, f, indent=2, default=str)
        logger.info(f"Dumped {len(ami_hash)} AMI entries to {filename}")
    except Exception as e:
        logger.error(f"Error dumping AMI cache to {filename}: {e}")

def write_csv(outfile, data, write_header=False):
    """Write the EC2 instance data to a CSV file."""
    fieldnames = [
        'AccountId', 'AccountName', 'Region', 'InstanceId', 'InstanceName', 'LaunchTime', 'State',
        'StateTransitionReason', 'StateTransitionTime', 'ImageId', 'PublicIPAddress', 'KeyName',
        'PlatformDetails', 'HttpTokens', 'IAMRole', 'DiskSizeGB',
        'AmiName', 'OSVersion', 'AmiDescription', 'AmiCreationDate', 'AmiOwner', 'AmiImageOwnerAlias', 'AmiDeprecationTime',
        'AmiImdsSupport', 'AmiLastLaunchedTime', 'AmiImageAllowed', 'AmiSourceImageId', 'AmiSourceName',
        'AncestorAmiId', 'AncestorAmiName', 'AncestorOSVersion', 'AmiState', 'AmiPublic'
    ]
    mode = 'w' if write_header else 'a'
    with open(outfile, mode=mode, newline='') as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames)
        if write_header:
            writer.writeheader()
        writer.writerows(data)
    logger.info(f"CSV report {'initialized' if write_header else 'updated'} at {outfile}")

def main(args=None):
    parser = argparse.ArgumentParser(description='Fetch EC2 instance and AMI details across all accounts in the organization.')
    parser.add_argument('--assume-role', required=True, help='The IAM Role to assume into each account')
    parser.add_argument('--role-session-name', default='ec2_instance_ami_report', help='The RoleSession Name for assuming the role')
    parser.add_argument('--outfile', default='ec2_instance_report.csv', help='The output CSV file name')
    parser.add_argument('--load-amis', help='JSON file to load cached AMI data from')
    parser.add_argument('--dump-amis', help='JSON file to dump cached AMI data to')
    if args is None:
        args = parser.parse_args()
    else:
        args = parser.parse_args(args)

    # Load AMI cache if specified
    if args.load_amis:
        load_ami_cache(args.load_amis)

    # Get all account IDs in the organization
    accounts = list_accounts()

    # Initialize the CSV file with headers
    write_csv(args.outfile, [], write_header=True)

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
                # Write to CSV after each region completes
                if instances:
                    write_csv(args.outfile, instances, write_header=False)
            except ClientError as e:
                logger.warning(f"Region {region} is blocked due to permissions: {e}")

    # Dump AMI cache if specified
    if args.dump_amis:
        dump_ami_cache(args.dump_amis)

if __name__ == '__main__':
    dump_file = None
    try:
        import sys
        # Parse args early to get dump-amis flag
        parser = argparse.ArgumentParser(description='Fetch EC2 instance and AMI details across all accounts in the organization.')
        parser.add_argument('--assume-role', required=True, help='The IAM Role to assume into each account')
        parser.add_argument('--role-session-name', default='ec2_instance_ami_report', help='The RoleSession Name for assuming the role')
        parser.add_argument('--outfile', default='ec2_instance_report.csv', help='The output CSV file name')
        parser.add_argument('--load-amis', help='JSON file to load cached AMI data from')
        parser.add_argument('--dump-amis', help='JSON file to dump cached AMI data to')
        args = parser.parse_args()
        dump_file = args.dump_amis

        main(sys.argv[1:])
    except KeyboardInterrupt:
        logger.info("\nOperation cancelled by user (Ctrl-C)")
        if dump_file:
            logger.info("Saving AMI cache before exit...")
            dump_ami_cache(dump_file)
        exit(0)
    except Exception as e:
        logger.critical(f"Fatal error: {e}")
        raise
