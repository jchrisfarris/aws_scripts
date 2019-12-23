#!/usr/bin/env python3


# Python script to copy all rows from one table to another

import sys, argparse, os
import boto3
from botocore.exceptions import ClientError

def do_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", help="print debugging info", action='store_true')
    parser.add_argument("--source", help="Source Tablename", required=True)
    parser.add_argument("--dest", help="dest Tablename", required=True)
    # parser.add_argument("--key_attribute", help="primary key")
    parser.add_argument("--dest-profile", help="Use this AWS Profile to write to the destination table (if in a different account)")
    parser.add_argument("--dest-region", help="Use this AWS Profile to write to the destination table (if in a different account)", default=os.environ['AWS_DEFAULT_REGION'])

    args = parser.parse_args()

    return(args)

def main(args):
    # Connect to the table.
    dynamodb = boto3.resource('dynamodb')
    src_table = dynamodb.Table(args.source)

    dest_region = args.dest_region

    if args.dest_profile:
        dest_session = boto3.Session(profile_name=args.dest_profile, region_name=dest_region)
    else:
        dest_session = boto3.Session(region_name=dest_region)

    dest_dynamodb = dest_session.resource('dynamodb')
    dest_table = dest_dynamodb.Table(args.dest)

    batch = dest_table.batch_writer()
    response = src_table.scan()
    while 'LastEvaluatedKey' in response :
        for item in response['Items']:
            print(".")
            batch.put_item(Item=item)
        response = src_table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
    for item in response['Items']:
        print(".")
        batch.put_item(Item=item)
    # FIXME - make sure all entries are written
    batch.__exit__(None, None, None)

if __name__ == '__main__':
    try:
        args = do_args()
        main(args)
        exit(0)
    except KeyboardInterrupt:
        exit(1)