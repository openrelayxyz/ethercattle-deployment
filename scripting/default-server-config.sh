#!/bin/bash -xe
yum install -y aws-cfn-bootstrap

if [ "$(arch)" == "x86_64" ]
then
  ARCH="amd64"
elif [ "$(arch)" == "aarch64" ]
then
  ARCH="arm64"
fi

sysctl -p || true
GETH_BIN="geth-linux-$ARCH"
LOGS_BIN="journald-cloudwatch-logs-$ARCH"
aws s3 cp s3://${S3GethBucketName}/${ECGethVersion}/$GETH_BIN /usr/bin/geth
aws s3 cp s3://${S3GethBucketName}/$LOGS_BIN /usr/local/bin/journald-cloudwatch-logs
aws s3 cp s3://${S3GethBucketName}/peerManagerAuth.py /usr/local/bin/peerManager.py
chmod +x /usr/bin/geth
chmod +x /usr/local/bin/journald-cloudwatch-logs
chmod +x /usr/local/bin/peerManager.py
mkdir -p /var/lib/journald-cloudwatch-logs/
mkdir -p /var/lib/ethereum
mount -o barrier=0,data=writeback,noatime /dev/sdf /var/lib/ethereum
mkdir -p /var/lib/ethereum/overlay
resize2fs /dev/sdf
useradd -r geth

echo "/dev/sdf  /var/lib/ethereum    ext4   barrier=0,data=writeback,noatime  1   1" >> /etc/fstab

ignore="$(readlink -f /dev/sd*) $(readlink -f /dev/xvd*)"
cutignore="$(for x in $ignore ; do echo $x | cut -c -12; done | uniq)"
devices="$(ls /dev/nvme* | grep -E 'n1$')" || devices=""
cutdevices="$(for x in $devices ; do echo $x | cut -c -12; done | uniq)"
localnvme=$(for d in $cutdevices; do if ! $(echo "$cutignore"| grep -q $d) ; then echo $d; fi ; done)
if [ ! -z "$localnvme" ]
then
  mkfs.ext4 $localnvme
  mount -o barrier=0,data=writeback $localnvme /var/lib/ethereum/overlay
  echo "$localnvme  /var/lib/ethereum/overlay    ext4   barrier=0,data=writeback,noatime  1   1" >> /etc/fstab
elif [ -e /dev/sdg ]
then
  mkfs.ext4 /dev/sdg
  mount -o barrier=0,data=writeback /dev/sdg /var/lib/ethereum/overlay
  echo "/dev/sdg  /var/lib/ethereum/overlay    ext4   barrier=0,data=writeback,noatime  1   1" >> /etc/fstab
fi

chown -R geth /var/lib/ethereum

yum install -y https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/$ARCH/latest/amazon-cloudwatch-agent.rpm nmap-ncat jq python-pip jq fio || true
pip install kafka-python
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c ssm:${MetricsConfigParameter} -s

crontab -l >  newcrontab || true
echo "5,20,35,50 * * * * /usr/bin/sh -c 'for x in \$(ls /dev/sd*) ; do echo resizing \$(readlink -f \$x) if needed; /usr/sbin/resize2fs \$(readlink -f \$x) ; done'" >> newcrontab
crontab newcrontab


printf "[Unit]
Description=journald-cloudwatch-logs
Wants=basic.target
After=basic.target network.target

[Service]
ExecStart=/usr/local/bin/journald-cloudwatch-logs /usr/local/etc/journald-cloudwatch-logs.conf
KillMode=process
Restart=on-failure
RestartSec=42s" > /etc/systemd/system/journald-cloudwatch-logs.service

echo "geth        hard nofile 500000" >> /etc/security/limits.conf
echo "geth        soft nofile 500000" >> /etc/security/limits.conf

systemctl daemon-reload

sleep 5 #TODO- workaround for a deadlock on topic creation


systemctl enable amazon-cloudwatch-agent.service
systemctl start amazon-cloudwatch-agent.service
systemctl enable journald-cloudwatch-logs
systemctl start journald-cloudwatch-logs

fio --filename=/dev/sdf --rw=read --bs=128k --iodepth=32 --ioengine=libaio --prio=7 --prioclass=3 --thinktime=2 --rate_iops=$((${DiskSize} * 3 - 100 )) --direct=1 --name=volume-initialize &
export AWS_DEFAULT_REGION=${AWS::Region}
VOLUME_ID=$(aws ec2 describe-volumes --filters Name=attachment.instance-id,Values="$(curl http://169.254.169.254/latest/meta-data/instance-id)" | jq '.Volumes[] | select(. | .Attachments[0].Device == "/dev/sdf") | .VolumeId' -cr)
wait
aws ec2 modify-volume --volume-id $VOLUME_ID --volume-type gp2 &
