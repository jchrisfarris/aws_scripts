#!/usr/bin/env python3


# Generate an HTML page with the cross-account role links for this payer.

import sys, argparse, os
import boto3
from botocore.exceptions import ClientError

assume_role_link = "<a href=\"https://signin.aws.amazon.com/switchrole?account={}&roleName={}&displayName={}\">{}</a>"


def do_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", help="print debugging info", action='store_true')
    parser.add_argument("--filename", help="Where to write the AWS config file", required=True)
    parser.add_argument("--rolename", help="Role Name to Assume", required=True)
    parser.add_argument("--source-profile", help="Name of profile which will do the assume role", required=True)
    args = parser.parse_args()
    return(args)

def main(args):

    accounts = list_accounts()

    config_file = f"""
[default]
cli_pager=
signature_version=s3v4
output=json
cli_history=enabled
region=us-east-1

[profile {args.source_profile}]

"""
    for a in accounts:
        config_file += f"""
# {a['Name']}
[profile {a['Id']}]
role_arn = arn:aws:iam::{a['Id']}:role/{args.rolename}
source_profile = {args.source_profile}

        """

    file = open(args.filename, "w")
    file.write(config_file)
    file.close()
    exit(0)

def list_accounts():
    try:
        org_client = boto3.client('organizations')
        output = []
        response = org_client.list_accounts(MaxResults=20)
        while 'NextToken' in response:
            output = output + response['Accounts']
            response = org_client.list_accounts(MaxResults=20, NextToken=response['NextToken'])

        output = output + response['Accounts']
        return(output)
    except ClientError as e:
        if e.response['Error']['Code'] == 'AWSOrganizationsNotInUseException':
            print("AWS Organiations is not in use or this is not a payer account")
            return(None)
        else:
            raise ClientError(e)

if __name__ == '__main__':
    try:
        args = do_args()
        main(args)
        exit(0)
    except KeyboardInterrupt:
        exit(1)