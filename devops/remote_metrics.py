import os
import boto3
import json
import urllib
import datetime

client = boto3.client('cloudwatch')
q = '{"jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id": 1}'.encode("utf8")


def handler(event, context):
    for url in os.environ["RPC_URL"].split(","):
        request = urllib.request.Request(url, data=q, headers={"Content-Type": "application/json"})
        result = json.load(urllib.request.urlopen(request))["result"]
        client.put_metric_data(
            Namespace="BlockData",
            MetricData=[{
                'MetricName': "RemoteBlockNumber",
                'Dimensions': [{"Name": "provider", "Value": url}],
                'Timestamp': datetime.datetime.utcnow(),
                'Value': int(result, 16),
                'Unit': "None",
            }]
        )
