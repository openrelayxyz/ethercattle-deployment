import boto3
import os

ec2 = boto3.client('ec2')
keep_count = int(os.environ.get("KEEP_COUNT", 4))


def handler(event, context):
    rsp = ec2.describe_snapshots(
        Filters=[{
            "Name": "tag:cluster",
            "Values": [os.environ.get("CLUSTER_ID")]
        }]
    )
    stale_snapshots = sorted(
        [i for i in rsp["Snapshots"] if i["Progress"] == "100%"],
        key=lambda i: i["StartTime"]
    )[:-keep_count]
    for snapshot in stale_snapshots:
        ec2.delete_snapshot(
            SnapshotId=snapshot["SnapshotId"]
        )
