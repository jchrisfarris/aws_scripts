#!/usr/bin/env python3


# Generate an HTML page with the cross-account role links for this payer.

import sys, argparse, os
import datetime
import boto3
from time import sleep
import time
from botocore.exceptions import ClientError

assume_role_link = "<a href=\"https://signin.aws.amazon.com/switchrole?account={}&roleName={}&displayName={}\">{}</a>"


def do_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", help="print debugging info", action='store_true')
    parser.add_argument("--filename", help="Where to write the html file", required=True)
    parser.add_argument("--rolename", help="Role Name to Assume", default="OrganizationAccountAccessRole")
    args = parser.parse_args()
    return(args)

def main(args):

    accounts = list_accounts()

    html_file = f"""
<html>
<head>
<title>AWS Account Inventory</title>
<link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.2.1/css/bootstrap.min.css" integrity="sha384-GJzZqFGwb1QTTN6wy59ffF1BuGJpLSa9DkKMp0DgiMDm4iYMj70gZWKYbI706tWS" crossorigin="anonymous">
</head>
<body style="padding:10;">
<h1>AWS Account Inventory</h1>
Total Active Accounts:  {len(accounts)}

<table class="table table-sm table-bordered table-hover">
<thead class="thead-light">
    <tr>
        <th scope="col">Account Name</th>
        <th scope="col">Account ID</th>
        <th scope="col">Root Email</th>
        <th scope="col">Status</th>
        <th scope="col">Assume Role Link</th>
    </tr>
</thead>
"""
    for a in accounts:
        link = assume_role_link.format(a['Id'], args.rolename, a['Name'], a['Name'])
        html_file += f"""
        <tr>
            <th scope="row">{a['Name']}</th>
            <td>{a['Id']}</td>
            <td>{a['Email']}</td>
            <td>{a['Status']}</td>
            <td>{link}</td>
        </tr>
        """

    html_file += f"""
</table>
<font size=-2>Page Generated on {datetime.datetime.now()}</font>
</body></html>
"""

    file = open(args.filename, "w")
    file.write(html_file)
    file.close()
    exit(0)

def list_accounts():
    try:
        org_client = boto3.client('organizations')
        output = []
        response = org_client.list_accounts(MaxResults=20)
        while 'NextToken' in response:
            output = output + response['Accounts']
            time.sleep(1)
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
