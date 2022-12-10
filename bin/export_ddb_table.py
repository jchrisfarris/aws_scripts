#!/usr/bin/env python3


# Python script export all rows of a DDB Table. 

import sys, argparse
import boto3
from botocore.exceptions import ClientError
import csv
from pprint import pprint


def do_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", help="print debugging info", action='store_true')
    parser.add_argument("--source", help="Source Tablename", required=True)
    parser.add_argument("--dest", help="dest filename", required=True)
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

    all_items = []
    all_keys = []
    response = src_table.scan()
    while 'LastEvaluatedKey' in response :
        for item in response['Items']:
            all_items.append(item)
            all_keys += item.keys()
        response = src_table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
    for item in response['Items']:
        all_items.append(item)
        all_keys += item.keys()

    unique_keys = list(dict.fromkeys(all_keys))
    print(unique_keys)

    csvfile = open(args.dest, 'w')
    writer = csv.DictWriter(csvfile, delimiter=',', quotechar='"', quoting=csv.QUOTE_ALL, fieldnames=unique_keys)
    writer.writeheader()
    for i in all_items:
        writer.writerow(i)
    csvfile.close()


if __name__ == '__main__':
    try: 
        args = do_args()
        main(args)
        exit(0)
    except KeyboardInterrupt:
        exit(1)