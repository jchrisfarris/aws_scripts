#!/usr/bin/env python3
# Copyright PrimeHarbor Technologies, LLC
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

from botocore.exceptions import ClientError
import boto3
import json
import os
import csv

import logging
logger = logging.getLogger()
logger.setLevel(getattr(logging, os.getenv('LOG_LEVEL', default='INFO')))
logging.getLogger('botocore').setLevel(logging.WARNING)
logging.getLogger('boto3').setLevel(logging.WARNING)
logging.getLogger('urllib3').setLevel(logging.WARNING)

def main(args, logger):

    PRINCIPALS={
        'USER': {},
        'GROUP': {}
    }
    DATA = []

    sso_client = boto3.client('sso-admin')
    ids_client = boto3.client('identitystore')
    try:
        instance_arn = get_instance_arn(sso_client)
    except Exception as e:
        logger.critical(f"Failed to get InstanceArn: {e}")
        exit(1)
    try:
        identity_store_id = get_identity_store_id(sso_client)
    except Exception as e:
        logger.critical(f"Failed to get IdentityStoreId: {e}")
        exit(1)


    fieldnames = ['User Name', 'Email', 'Group Name']

    # Order of battle:
    # 1. List all accounts
    # 2. For each Account, list the permission sets provisioned to the account
    # 3. For each permission set, list the account assignments
    # 4. For the User or Group, get the name and the permission set, save that in the list DATA

    group_paginator = ids_client.get_paginator('list_groups')
    user_paginator = ids_client.get_paginator('list_group_memberships')

    response_iterator = group_paginator.paginate(IdentityStoreId=identity_store_id)

    with open(args.outfile, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        for group_page in response_iterator:
            for group in group_page['Groups']:
                logger.info(f"Found Group {group['DisplayName']} as {group['GroupId']}")
                user_iterator = user_paginator.paginate(IdentityStoreId=identity_store_id, GroupId=group['GroupId'])
                for user_page in user_iterator:
                    for membership in user_page['GroupMemberships']:
                        user = lookup_user(identity_store_id, membership['MemberId']['UserId'])
                        logger.debug(f"\t{user['DisplayName']}, {user['UserName']}, {group['DisplayName']}")
                        writer.writerow({
                            'User Name': user['DisplayName'],
                            'Email': user['UserName'],
                            'Group Name': group['DisplayName']
                            })


def lookup_permset(instance_arn, arn):
    try:
        sso_client = boto3.client('sso-admin')
        return(sso_client.describe_permission_set(InstanceArn=instance_arn, PermissionSetArn=arn)['PermissionSet']['Name'])
    except Exception as e:
        logger.warning(f"Got exception looking up permission set {arn}: {e}")
        return("NotFound")


def lookup_user(identity_store_id, user_id):
    try:
        ids_client = boto3.client('identitystore')
        return(ids_client.describe_user(IdentityStoreId=identity_store_id, UserId=user_id))
    except Exception as e:
        logger.warning(f"Got exception looking up user {user_id}: {e}")
        return("NotFound")

def lookup_group(identity_store_id, group_id):
    try:
        ids_client = boto3.client('identitystore')
        return(ids_client.describe_group(IdentityStoreId=identity_store_id, GroupId=group_id)['DisplayName'])
    except Exception as e:
        logger.warning(f"Got exception looking up group {group_id}: {e}")
        return("NotFound")

def get_consolidated_billing_subaccounts():
    # Returns: [
    #         {
    #             'Id': 'string',
    #             'Arn': 'string',
    #             'Email': 'string',
    #             'Name': 'string',
    #             'Status': 'ACTIVE'|'SUSPENDED',
    #             'JoinedMethod': 'INVITED'|'CREATED',
    #             'JoinedTimestamp': datetime(2015, 1, 1)
    #         },
    #     ],
    org_client = boto3.client('organizations')
    output = []
    response = org_client.list_accounts(MaxResults=20)
    while 'NextToken' in response:
        output = output + response['Accounts']
        response = org_client.list_accounts(MaxResults=20, NextToken=response['NextToken'])
    output = output + response['Accounts']
    return(output)
# end get_consolidated_billing_subaccounts()


def get_instance_arn(sso_client):
    response = sso_client.list_instances()
    return(response['Instances'][0]['InstanceArn'])

def get_identity_store_id(sso_client):
    response = sso_client.list_instances()
    return(response['Instances'][0]['IdentityStoreId'])

def do_args():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", help="print debugging info", action='store_true')
    parser.add_argument("--error", help="print error info only", action='store_true')
    parser.add_argument("--outfile", help="Name of cvs file to create", required=True)

    args = parser.parse_args()

    return(args)

if __name__ == '__main__':

    args = do_args()

    # Logging idea stolen from: https://docs.python.org/3/howto/logging.html#configuring-logging
    # create console handler and set level to debug
    ch = logging.StreamHandler()
    if args.error:
        logger.setLevel(logging.ERROR)
    elif args.debug:
        logger.setLevel(logging.DEBUG)
    else:
        logger.setLevel(logging.INFO)

    # create formatter
    # formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    formatter = logging.Formatter('%(levelname)s - %(message)s')
    # add formatter to ch
    ch.setFormatter(formatter)
    # add ch to logger
    logger.addHandler(ch)

    try:
        main(args, logger)
    except KeyboardInterrupt:
        exit(1)