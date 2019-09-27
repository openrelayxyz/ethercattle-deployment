import boto3
import os
import datetime

ec2 = boto3.resource('ec2')


def handler(event, context):
    ec2.create_instances(
        MaxCount=1,
        MinCount=1,
        LaunchTemplate={
            "LaunchTemplateId": os.environ.get("LAUNCH_TEMPLATE_ID"),
            "Version": os.environ.get("LAUNCH_TEMPLATE_VERSION"),
        },
        SubnetId=os.environ.get("SUBNET_ID"),
        InstanceMarketOptions={
            'MarketType': 'spot',
            'SpotOptions': {
                'SpotInstanceType': 'one-time',
            }
        }
    )
