#!/usr/bin/env python


# Python script to delete all rows with a given Id value.

import boto.dynamodb
import boto.dynamodb.condition as condition
import sys, argparse
import boto3
from botocore.exceptions import ClientError

def do_args():
	parser = argparse.ArgumentParser()
	parser.add_argument("--debug", help="print debugging info", action='store_true')
	parser.add_argument("--table", help="Tablename")
	parser.add_argument("--key_attribute", help="primary key")

	args = parser.parse_args()

	if args.table == "":
		print "Must specify --table"
		exit(1)
	if args.key_attribute == "":
		print "Must specify --key_attribute"
		exit(1)

	return(args)

def main(args):
	# Connect to the table.
	dynamodb = boto3.resource('dynamodb')
	my_table = dynamodb.Table(args.table)

	# Print a warning
	print 'About to delete all rows from table {}!!!'.format(args.table)
	print 'Are you sure? (type "YES" to continue)'
	response = raw_input().upper()
	if response != 'YES':
		print 'OK, not deleting anything!'
		quit()

	batch = my_table.batch_writer()
	response = my_table.scan()
	while 'LastEvaluatedKey' in response :
		for item in response['Items']:
			batch.delete_item(Key={args.key_attribute: item[args.key_attribute] } )
		response = my_table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
	for item in response['Items']:
		batch.delete_item(Key={args.key_attribute: item[args.key_attribute] } )


if __name__ == '__main__':
	try: 
		args = do_args()
		main(args)
	except KeyboardInterrupt:
		exit(1)