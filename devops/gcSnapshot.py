import boto3
import os
import datetime

ec2 = boto3.client('ec2')
keep_count = int(os.environ.get("KEEP_COUNT", 2))
today_keep_count = int(os.environ.get("TODAY_KEEP_COUNT", 2))


def handler(event, context):
    rsp = ec2.describe_snapshots(
        Filters=[{
            "Name": "tag:cluster",
            "Values": [os.environ.get("CLUSTER_ID")]
        }]
    )
    sorted_snaps = sorted(
        [i for i in rsp["Snapshots"] if i["Progress"] == "100%"],
        key=lambda i: i["StartTime"]
    )
    today = datetime.datetime.combine(
            datetime.date.today(), datetime.datetime.min.time()
        ).replace(tzinfo=sorted_snaps[0]["StartTime"].tzinfo)
    yesterday = today - datetime.timedelta(days=1)
    today_snaps = [i for i in sorted_snaps if i["StartTime"] >= today]
    yesterday_snaps = [i for i in sorted_snaps if yesterday <= i["StartTime"] < today]
    older_snaps = [i for i in sorted_snaps if i["StartTime"] < yesterday]
    for snapshot in today_snaps[:-today_keep_count] + older_snaps[:-keep_count] + yesterday_snaps[:-1]:
        ec2.delete_snapshot(
            SnapshotId=snapshot["SnapshotId"]
        )
