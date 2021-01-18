import boto3
import os
import time

ec2Client = boto3.client('ec2')
taggingClient = boto3.client('resourcegroupstaggingapi')

def cleanup_detached_volumes():
    res = taggingClient.get_resources(TagFilters=[{"Key": "DELETE_ON_DETACH", "Values": ["True"]}])
    for mapping in res["ResourceTagMappingList"]:
        volume_id = mapping["ResourceARN"].split("/")[1]
        try:
            ec2Client.delete_volume(VolumeId = volume_id)
        except Exception:
            pass

def handler(event, context):
    if event["detail"]["state"] != "pending":
        cleanup_detached_volumes()  # Run just in case something got missed previously
        return
    instance_details = ec2Client.describe_instances(InstanceIds=[event["detail"]["instance-id"]])
    instance_type = instance_details["Reservations"][0]["Instances"][0]["InstanceType"]
    family, size = instance_type.split(".")
    if family.endswith("d"):
        cleanup_detached_volumes()  # Run just in case something got missed previously
        return
    tags = {i["Key"]: i["Value"] for i in instance_details["Reservations"][0]["Instances"][0]["Tags"]}
    if tags.get(os.environ.get("TAG_NAME", "VOLUME_MGMT_GROUP")) != os.environ.get("TAG_VALUE", "X"):
        cleanup_detached_volumes()  # Run just in case something got missed previously
        return
    volumes = {a["DeviceName"]: a["Ebs"]["VolumeId"] for a in instance_details["Reservations"][0]["Instances"][0]["BlockDeviceMappings"]}
    # TODO: Tag volume, detach volume, subsequent event will watch for detach transition and delete
    ec2Client.create_tags(Resources=[volumes[os.environ["VOLUME_NAME"]]], Tags=[{"Key": "DELETE_ON_DETACH", "Value": "True"}])
    ec2Client.detach_volume(
        Device: os.environ["VOLUME_NAME"],
        InstanceId: event["detail"]["instance-id"],
        VolumeId: volumes[os.environ["VOLUME_NAME"]],
    )
    while ec2Client.describe_volumes(VolumeIds=[volumes[os.environ["VOLUME_NAME"]]])["Volumes"][0]["State"] != "available":
        time.sleep(0.5)
    cleanup_detached_volumes()
