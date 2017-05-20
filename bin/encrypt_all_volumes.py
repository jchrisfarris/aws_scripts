#!/usr/bin/python

# Script to take an instance and encrypt all it's volumes

import boto3
import botocore
from multiprocessing import Pool
import argparse
import sys
import signal
import time


parser = argparse.ArgumentParser()
parser.add_argument("--debug", help="print debugging info", action='store_true')
parser.add_argument("--key", help="kms key id (not arn)")
parser.add_argument("instance_id", help="Instance ID you want to encrypt")
parser.add_argument("--stop", help="Stop the instance first", action='store_true')
parser.add_argument("--single", help="Run Single Threaded for testing", action='store_true')
parser.add_argument("--dry-run", help="Do a Dry-Run only", action='store_true')
parser.add_argument("--no-start", help="Don't start instance whend done", action='store_true')

args = parser.parse_args()


def get_kms_arn(key_name):
    client = boto3.client('kms')

    if key_name.startswith("arn"):
        # we were passed in an arm
        kms_key_id = key_name
    elif len(key_name) == 36:
        # we were passed in a key ID (fe245bc5-d1e2-dead-beef-deadbeefb0ab)
        kms_key_id = key_name
    else:
        # Assume it's an alias otherwise
        kms_key_id = "alias/" + key_name
    
    try:    
        response = client.describe_key(KeyId=kms_key_id)
    except botocore.exceptions.ClientError as e:
        print("Error finding key {}: {}".format(key_name, e.message))
        sys.exit(1)

    if response['KeyMetadata']['Enabled'] != True:
        print("{} key is not available".format(kms_key_id))
    else:
        return(response['KeyMetadata']['Arn'])
# end get_kms_arn()

def encrypt_volume(original_volume_id):
    waiter_snapshot_complete = ec2_client.get_waiter("snapshot_completed")
    waiter_volume_available = ec2_client.get_waiter("volume_available")
    waiter_volume_in_use = ec2_client.get_waiter("volume_in_use")


    print("-Encrypting {}".format(original_volume_id))
    original_volume=ec2.Volume(original_volume_id)
    # original_volume.load()

    """ Step 1: Take snapshot of volume """
    print("-Create snapshot of volume ({}) for {}:{}".format(original_volume_id, 
        original_volume.attachments[0][u'InstanceId'], original_volume.attachments[0][u'Device']))

    if args.dry_run:
        # if original_volume_id == "vol-05fffd15a706a6ab1":
        #     time.sleep(2)
        #     print("Fake Bad thread throwing exception!!!")
        #     raise botocore.exceptions.ClientError([1], "This is a test failure")
        time.sleep(10)
        print "Testing Threads"
        return(1)

    # Tag the original volume as we don't delete it at the end for safety.
    original_volume.create_tags( Tags=[{
        'Key': 'volume_encryption_saved_attachment_info',
        'Value': "{}:{}".format(original_volume.attachments[0][u'InstanceId'], original_volume.attachments[0][u'Device'])
    }])

    try:
        snapshot = ec2.create_snapshot(
            VolumeId=original_volume_id,
            Description="Snapshot of volume ({}) for {}:{}".format(original_volume_id, 
                original_volume.attachments[0][u'InstanceId'], original_volume.attachments[0][u'Device'])
        )
    except botocore.exceptions.ClientError as e:
        print "ERROR creating snapshot for {}: {}".format(original_volume_id, e.message)        
        return(1)

    try:
        waiter_snapshot_complete.wait( SnapshotIds=[snapshot.id])
    except botocore.exceptions.WaiterError as e:
        snapshot.delete()
        print "TIMEOUT creating snapshot for {}: {}".format(original_volume_id, e.message)        
        return(1)

    # """ Step 2: Create encrypted volume """
    print("-Create encrypted copy of snapshot {} for {}:{}".format(snapshot.id, 
        original_volume.attachments[0][u'InstanceId'], original_volume.attachments[0][u'Device']))

    try:
        snapshot_encrypted_dict = snapshot.copy(
            SourceRegion=session.region_name,
            Description="Encrypted copy of snapshot ({}) for {}"
                        .format(snapshot.id, original_volume_id),
            KmsKeyId=kms_arn,
            Encrypted=True,
        )
    except botocore.exceptions.ClientError as e:
        print "ERROR creating encrypted snapshot for {}: {}".format(original_volume_id, e.message)
        return(1)

    snapshot_encrypted = ec2.Snapshot(snapshot_encrypted_dict["SnapshotId"])

    try:
        waiter_snapshot_complete.wait( SnapshotIds=[snapshot_encrypted.id])
    except botocore.exceptions.WaiterError as e:
        snapshot.delete()
        snapshot_encrypted.delete()
        print "TIMEOUT creating encrypted snapshot for {}: {}".format(original_volume_id, e.message)
        return(1)

    print("-Create encrypted volume from snapshot for {}".format(original_volume_id))
    try:
        volume_encrypted = ec2.create_volume(
            SnapshotId=snapshot_encrypted.id,
            AvailabilityZone=instance.placement["AvailabilityZone"]
        )
    except botocore.exceptions.ClientError as e:
        print "ERROR creating volume from encrypted snapshot {}: {}".format(original_volume_id, e.message)
        return(1)   

    try:
        waiter_volume_available.wait( VolumeIds=[ volume_encrypted.id ] )
    except botocore.exceptions.WaiterError as e:
        snapshot.delete()
        snapshot_encrypted.delete()
        volume_encrypted.delete()
        print "TIMEOUT creating volume from encrypted snapshot {}: {}".format(original_volume_id, e.message)
        return(1)


    print("-Detach volume {}".format(original_volume_id))
    try:
        instance.detach_volume( VolumeId=original_volume_id )
    except botocore.exceptions.ClientError as e:
        print "ERROR detaching original volume {}: {}".format(original_volume_id, e.message)
        return(1)

    try:
        waiter_volume_available.wait( VolumeIds=[ original_volume_id ] )
    except botocore.exceptions.WaiterError as e:
        snapshot.delete()
        snapshot_encrypted.delete()
        volume_encrypted.delete()
        print "TIMEOUT detaching original volume {}: {}".format(original_volume_id, e.message)
        return(1)   

    print("-Attach volume {} as {}".format(volume_encrypted.id, original_volume.attachments[0][u'Device']))
    try:
        instance.attach_volume(
            VolumeId=volume_encrypted.id,
            Device=original_volume.attachments[0][u'Device']
        )
    except botocore.exceptions.ClientError as e:
        print "ERROR attaching new volume {} to replace {}: {}".format(volume_encrypted.id, original_volume_id, e.message)
        return(1)

    try:
        waiter_volume_in_use.wait( VolumeIds=[ volume_encrypted.id ] )
    except botocore.exceptions.WaiterError as e:
        snapshot.delete()
        snapshot_encrypted.delete()
        print "TIMEOUT attaching new volume {} to replace {}: {}".format(volume_encrypted.id, original_volume_id, e.message)
        return(1) 

    # Cleanup
    snapshot.delete()
    snapshot_encrypted.delete()

    return volume_encrypted.id
# end encrypt_volume()

# def init_worker():
#     signal.signal(signal.SIGINT, signal.SIG_IGN)

# Start main
if __name__ == '__main__':

    # print("Using profile {}".format(profile))
    # Create custom session
    session = boto3.session.Session()
    ec2 = session.resource("ec2")
    ec2_client = session.client("ec2")

    waiter_instance_stopped = ec2_client.get_waiter("instance_stopped")

    try:
        instance = ec2.Instance(args.instance_id)
        instance.load()
    except botocore.exceptions.ClientError as e:
        print("Cannot find instance {}. Aborting...".format(args.instance_id))
        sys.exit(1)


    if args.dry_run:
        print("Executing a Dry-Run. will not Stop Instance, or encrypt volumes.")
    else:
        ## Do some error checking on the instance's running status
        if instance.state['Name'] == "running":
            if args.stop:
                print("Instance is running. Stopping it now...")
                instance.stop()
                try:
                    waiter_instance_stopped.wait( InstanceIds=[ args.instance_id ] )
                except botocore.exceptions.WaiterError as e:
                    print "ERROR: {} stopping {}. Aborting...".format(e, args.instance_id)
                    sys.exit(1)
            else:
                print("Instance {} is {}. Use --stop to stop a running instance.".format(args.instance_id, instance.state['Name']))
                sys.exit(1)
        elif instance.state['Name'] == "stopped":
            print("Instance is stopped. Can proceed.")
        else:
            print("Instance {} is not running or stopped. State: {}. Cannot proceed...".format(args.instance_id, instance.state['Name']))
            sys.exit(1)    

    if args.key:
        kms_arn = get_kms_arn(args.key)
    else:
        kms_arn = get_kms_arn("aws/ebs")

    initial_volume_count = len(instance.block_device_mappings)
    # volumes = instance.volumes.all()
    volumes = [v for v in instance.volumes.all()]

    volumes_to_encrypt = []

    print("Found {} volumes for {} to encrypt with {}".format(len(volumes), args.instance_id, kms_arn))
    for v in volumes:
    	if v.encrypted:
    		if v.kms_key_id != kms_arn:
    			print("volume {} is encrypted with wrong key {} should be {}".format(v.id, v.kms_key_id, kms_arn))
    			volumes_to_encrypt.append(v.id)
    		else:
    			print("volume {} is encrypted with correct key {}".format(v.id, v.kms_key_id))
    	else:
    		print("volume {} is not encrypted".format(v.id))
    		volumes_to_encrypt.append(v.id)

    if len(volumes_to_encrypt) == 0:
        print("No volumes to encrypt. Exiting...")
        sys.exit(0)

   

    if args.single:
        print("{} volumes to encrypt. Working single threaded.".format(len(volumes_to_encrypt)))
        for v in volumes_to_encrypt:
            encrypt_volume(v)
    else:
        print("{} volumes to encrypt. Need that many threads".format(len(volumes_to_encrypt)))

        original_sigint_handler = signal.signal(signal.SIGINT, signal.SIG_IGN)
        p = Pool(len(volumes_to_encrypt))
        signal.signal(signal.SIGINT, original_sigint_handler)
        try:
            res = p.map_async(encrypt_volume, volumes_to_encrypt)
            res.get(600)
        except KeyboardInterrupt:
            print "Caught KeyboardInterrupt, terminating workers"
            p.terminate()
        except Exception as e:
            print "Caught Other Exception {}".format(e.message)
        else:
            print "Quitting normally"
            p.close()
        p.join()

    if not args.dry_run:
        print("All Done. Starting instance now")
        # Make sure there are the right number of attachments, otherwise we don't want to start. eek!
        instance.reload() # re-ask AWS about the instance
        final_volume_count = len(instance.block_device_mappings)
        if final_volume_count != initial_volume_count:
            print("ERROR! initial volume_count doesn't match final volume count. Not starting instance!")
            sys.exit(1)
        else:
            if not args.no_start:
                instance.start()
            else:
                print("--no-start specified. Not starting instance")
    else:
        print("Dry-run, not starting instance")


