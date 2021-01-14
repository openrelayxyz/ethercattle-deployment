#!/usr/bin/env bash

printf "log_group = \"${FallBackLG}\"\nstate_file = \"/var/lib/journald-cloudwatch-logs/state\"" > /usr/local/etc/journald-cloudwatch-logs.conf

rm /var/lib/ethereum/geth.ipc || true
systemctl enable geth-fallback.service
systemctl start geth-fallback.service


/opt/aws/bin/cfn-init -v --stack ${AWS::StackName} --resource ReplicaLaunchTemplate --configsets cs_install --region ${AWS::Region}

if [ -f /usr/bin/replica-hook ]
then
  /usr/bin/replica-hook
fi
