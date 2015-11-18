#!/bin/bash

# I am an EC2 Instance.
# I have a tag called dnsname which is a fqdn that is hosted in Route53
# I have an instance profile with permission to the hosed zone
# I know my public address from instance data

# Get my public address
a_record=`curl http://169.254.169.254/latest/meta-data/public-ipv4`

# Get my instance ID so I can get my tags
INSTANCE_ID=`wget -qO- http://instance-data/latest/meta-data/instance-id`

# Get my region so I know what API endpoint to talk to
REGION=`wget -qO- http://instance-data/latest/meta-data/placement/availability-zone | sed 's/.$//'`

# get my "dnsname" tag
fqdn=`aws ec2 describe-tags --region $REGION --filter "Name=resource-id,Values=$INSTANCE_ID" --output=text | grep dnsname | awk '{print $NF}'`

if [ $? -ne 0 ] || [ -z "$fqdn" ] ; then
  echo "unable to find dnsname tag. Don't know how to proceed. Aborting...."
  exit 1
fi

name=`echo $fqdn | awk -F. '{print $1}'`
zone=`echo $fqdn | sed s/$name.//g`

echo "Updating $name in $zone to $a_record"

# Get the zone ID
zone_id=`aws route53 list-hosted-zones-by-name --region $REGION --dns-name $zone | grep Id | awk -F \/ '{print $3}' | sed s/\",//g | head -1`
echo $zone_id

if [ -z "$zone_id" ] ; then
  echo "zone ${zone} is not in route 53, or your Instance Role isn't working."
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
        "Name": "${name}.${zone}.",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [
          {
            "Value": "${a_record}"
          }
        ]
      }
    }
  ]
}
EOM

aws route53 change-resource-record-sets --hosted-zone-id $zone_id --region $REGION --change-batch file://$FILE
if [ $? -eq 0 ] ; then
  rm $FILE
  echo "Success!"
  exit
else
  exit 1
fi
