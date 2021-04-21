import boto3
import os
import datetime

ec2 = boto3.resource('ec2')

INSTANCE_TYPES = [
    "m5a.large",
    "m5.large",
    "m5d.large",
    "m5ad.large",
    "r5.large",
    "r5d.large",
    "r5a.large",
    "r5ad.large",
]


def handler(event, context):
    if os.environ.get("INSTANCE_TYPES"):
        instance_types = os.environ.get("INSTANCE_TYPES").split(",")
    else:
        instance_types = INSTANCE_TYPES
    for subnet in os.environ.get("SUBNET_ID").split(","):
        for instance_type in instance_types:
            try:
                ec2.create_instances(
                    InstanceType=instance_type,
                    MaxCount=1,
                    MinCount=1,
                    LaunchTemplate={
                        "LaunchTemplateId": os.environ.get("LAUNCH_TEMPLATE_ID"),
                        "Version": os.environ.get("LAUNCH_TEMPLATE_VERSION"),
                    },
                    SubnetId=subnet,
                    InstanceMarketOptions={
                        'MarketType': 'spot',
                        'SpotOptions': {
                            'SpotInstanceType': 'one-time',
                        }
                    }
                )
            except Exception:
                continue
            else:
                return
