import boto3
import os

client = boto3.client("ec2")

def sizeHandler(event, context):
    target_size = int(os.environ.get("VOLUME_SIZE"))
    volumes = client.describe_volumes(Filters=[
        {"Name": "tag:Name", "Values": ["%s-Master" % os.environ.get("KAFKA_TOPIC")]},
        {"Name":"attachment.device", "Values": ["/dev/sdf"]}
    ])["Volumes"]
    for volume in volumes:
        if volume["Size"] < target_size:
            client.modify_volume(
                VolumeId = volume["VolumeId"],
                Size = target_size,
            )
