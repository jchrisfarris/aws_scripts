#!/bin/bash

# This script will update an A Record in AWS Route 53. It assumes you are running this from an 
# EC2 instance with the proper IAM role, or that the API Keys are in your environment. 

# Capture the getopts
zone=$1
ip_addr=$2

if [ -z "$ip_addr"  ] ; then
  echo "usage: $0 <zone> <ip_addr_for_www>"
  exit 1
fi

# Get the zone ID
response=`aws route53 create-hosted-zone --name $zone --caller-reference $zone-$$`
if [ $? -ne 0 ] ; then
  echo "Failed to create zone."
  echo "Errored with: $response"
  exit 1
fi


zone_id=`aws route53 list-hosted-zones-by-name --dns-name $zone | grep Id | awk -F \/ '{print $3}' | sed s/\",//g | head -1`
echo $zone_id

if [ -z "$zone_id" ] ; then
  echo "zone ${zone} is not in route 53, or your IAM/APIkeys aren't working."
  exit 1
fi

FILE=/tmp/update_file.$$.json
cat > $FILE <<EOM
{
  "Comment": "A new record set for the zone.",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "www.${zone}.",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [
          {
            "Value": "${ip_addr}"
          }
        ]
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${zone}.",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [
          {
            "Value": "${ip_addr}"
          }
        ]
      }
    }
  ]
}
EOM

aws route53 change-resource-record-sets --hosted-zone-id $zone_id --change-batch file://$FILE
rm $FILE
