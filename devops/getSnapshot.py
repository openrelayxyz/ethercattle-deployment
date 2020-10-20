import boto3
import os
import datetime

ec2 = boto3.resource('ec2')

instance_types = [
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
    for instance_type in instance_types:
        for subnet in os.environ.get("SUBNET_ID").split(","):
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
