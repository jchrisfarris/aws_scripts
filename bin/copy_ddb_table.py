#!/usr/bin/env python3


# Python script to delete all rows with a given Id value.

import sys, argparse
import boto3
from botocore.exceptions import ClientError

def do_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", help="print debugging info", action='store_true')
    parser.add_argument("--source", help="Source Tablename")
    parser.add_argument("--dest", help="dest Tablename")
    # parser.add_argument("--key_attribute", help="primary key")

    args = parser.parse_args()

    if not hasattr(args, 'source') or args.source == "":
        print("Must specify --source")
        exit(1)
    if not hasattr(args, 'dest') or args.dest == "":
        print("Must specify --dest")
        exit(1)        
    # if args.key_attribute == "":
    #     print "Must specify --key_attribute"
    #     exit(1)

    return(args)

def main(args):
    # Connect to the table.
    dynamodb = boto3.resource('dynamodb')
    src_table = dynamodb.Table(args.source)
    dest_table = dynamodb.Table(args.dest)

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