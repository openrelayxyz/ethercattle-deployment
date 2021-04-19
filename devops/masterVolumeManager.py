import boto3
import os

client = boto3.client("ec2")

def sizeHandler(event, context):
    target_size = int(os.environ.get("VOLUME_SIZE"))
    volumes = client.describe_volumes(Filters=[
        {"Name": "tag:Name", "Values": [os.environ.get("VOLUME_NAME")]},
        {"Name":"attachment.device", "Values": ["ATTACHMENT_DEVICE"]}
    ])["Volumes"]
    for volume in volumes:
        if volume["Size"] < target_size:
            client.modify_volume(
                VolumeId = volume["VolumeId"],
                Size = target_size,
            )
            break # Only do one at a time to avoid the optimizing performance penalties hitting all masters at once


# TODO: Upload
