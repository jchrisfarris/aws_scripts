#!/usr/bin/env python3

import boto3
import os
import keyring
import sys
import getpass
from pprint import pprint

DURATION=28800

def parse_args():
    if len(sys.argv) < 2:
        sys.exit('Usage: %s account-name [username]' % sys.argv[0])

    account_name = sys.argv[1]

    if len(sys.argv) == 3:
        username = sys.argv[2]
    else:
        username = getpass.getuser()

    return(account_name, username)


def main(account_name, username=False):

    (API_KEY, SECRET_KEY) = get_perm_keys(account_name, username)

    (iam_username, mfa_serial) = get_my_mfa_serial_number(API_KEY, SECRET_KEY)

    non_mfa_sts_client = boto3.client('sts',
        aws_access_key_id = API_KEY,
        aws_secret_access_key = SECRET_KEY
    )

    token = input("MFA code for {}: ".format(iam_username))
    response = non_mfa_sts_client.get_session_token(
        DurationSeconds=DURATION,
        SerialNumber=mfa_serial,
        TokenCode=token
    )

    print("export AWS_ACCESS_KEY_ID={}".format(response['Credentials']['AccessKeyId']))
    print("export AWS_SECRET_ACCESS_KEY={}".format(response['Credentials']['SecretAccessKey']))
    print("export AWS_SESSION_TOKEN={}".format(response['Credentials']['SessionToken']))
    exit(0)

def get_my_mfa_serial_number(API_KEY, SECRET_KEY):
    try:
        client = boto3.client('iam',
            aws_access_key_id = API_KEY,
            aws_secret_access_key = SECRET_KEY
        )
        response = client.get_user()
        username = response['User']['UserName']
        arn = response['User']['Arn'].replace(':user/', ':mfa/')
        return(username, arn)
    except ClientError as e:
        print("Unable to get iam user details from AWS: {}".format(e))
        exit(1)
    except KeyError as e:
        print("IAM user details corrupt or missing: {}".format(e))
        exit(1)


def get_perm_keys(account, username=False):
    '''fetch permenant keys from keychain '''

    if username == False:
        username = getpass.getuser()

    keyring_user = "{}@{}".format(username, account)
    try:
        API_KEY = keyring.get_password(keyring_user, 'AWS_ACCESS_KEY_ID')
        SECRET_KEY = keyring.get_password(keyring_user, 'AWS_SECRET_ACCESS_KEY')
        return(API_KEY, SECRET_KEY)
    except:
        print("Unable to find KEY or SECRET for {}: {}".format(keyring_user, e))
        exit(1)



if __name__ == '__main__':
    (account_name, username) = parse_args()
    main(account_name, username)