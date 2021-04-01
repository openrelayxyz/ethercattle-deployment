#!/bin/bash -xe

SEP=$(echo "${KafkaBrokerURL}" | grep -q "?" && echo "&" || echo "?")
SEP_ESCAPED=$(echo "${KafkaBrokerURL}" | grep -q "?" && echo "\\&" || echo "?")
KAFKA_ESCAPED_URL="$(printf "${KafkaBrokerURL}"| sed 's^&^\\\\&^g')"

if [ -e /dev/sdg ]
then
  OVERLAY_FLAG="--datadir.overlay=/var/lib/ethereum/overlay"
fi
ignore="$(readlink -f /dev/sd*) $(readlink -f /dev/xvd*)"
cutignore="$(for x in $ignore ; do echo $x | cut -c -12; done | uniq)"
devices="$(ls /dev/nvme* | grep -E 'n1$')" || devices=""
cutdevices="$(for x in $devices ; do echo $x | cut -c -12; done | uniq)"
localnvme=$(for d in $cutdevices; do if ! $(echo "$cutignore"| grep -q $d) ; then echo $d; fi ; done)
if [ ! -z "$localnvme" ]
then
  OVERLAY_FLAG="--datadir.overlay=/var/lib/ethereum/overlay"
fi

totalm=$(free -m | awk '/^Mem:/{print $2}') ; echo $totalm
allocatesafe=$((totalm * 75 / 100))

printf "KafkaHostname=${KafkaBrokerURL}
KafkaTopic=${KafkaTopic}
NetworkId=${NetworkId}
infraName=${InfrastructureStack}
baseInfraName=${BaseInfrastructure}
network=${NetworkId}
ReplicaClusterVersion=${ReplicaClusterVersion}
AWS_REGION=${AWS::Region}
LOG_BLOCK_LIMIT=10000
FLUME_URL=${FlumeURL}" > /etc/systemd/system/ethcattle-vars


printf "[Unit]
Description=Ethereum go client replica
After=syslog.target network.target
[Service]
User=geth
Group=geth
Environment=HOME=/var/lib/ethereum
EnvironmentFile=/etc/systemd/system/ethcattle-vars
Type=simple
LimitNOFILE=655360
ExecStartPre=/usr/bin/bash -c '/usr/bin/geth replica --snapshot=false --cache=$allocatesafe ${ReplicaExtraFlags} ${FreezerFlags}  $OVERLAY_FLAG --kafka.broker=$KAFKA_ESCAPED_URL""$SEP_ESCAPED""fetch.default=8388608\\&max.waittime=25\\&avoid_leader=1  --datadir=/var/lib/ethereum --kafka.topic=${KafkaTopic} --replica.syncshutdown 2>>/tmp/geth-stderr'
ExecStart=/usr/bin/bash -c '/usr/bin/geth replica --snapshot=false --cache=$allocatesafe ${ReplicaExtraFlags} ${FreezerFlags} $OVERLAY_FLAG --kafka.broker=$KAFKA_ESCAPED_URL --datadir=/var/lib/ethereum --kafka.topic=${KafkaTopic} --kafka.txpool.topic=\$infraName-txpool  --kafka.tx.topic=\$NetworkId-tx --replica.startup.age=45  ${ReplicaHTTPFlag} ${ReplicaGraphQLFlag} ${ReplicaWebsocketsFlag}'
TimeoutStopSec=90
Restart=on-failure
TimeoutStartSec=86400
RestartSec=10s
[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/geth-replica.service

printf "[Unit]
Description=Ethereum go client replica
After=syslog.target network.target
[Service]
User=geth
Group=geth
Environment=HOME=/var/lib/ethereum
EnvironmentFile=/etc/systemd/system/ethcattle-vars
Type=simple
LimitNOFILE=655360
# ExecStartPre=/usr/bin/geth replica --snapshot=false ${FreezerFlags}  $OVERLAY_FLAG  --cache=$allocatesafe ${FreezerFlags} --kafka.broker=$KAFKA_ESCAPED_URL""$SEP_ESCAPED""fetch.default=8388608\\&max.waittime=25\\&avoid_leader=1  --datadir=/var/lib/ethereum --kafka.topic=${KafkaTopic} --replica.syncshutdown 2>>/tmp/geth-stderr || true
ExecStart=/usr/bin/bash -c '/usr/bin/geth ${FreezerFlags} ${MasterExtraFlags} --rpc.allow-unprotected-txs --snapshot=false --txlookuplimit=0 $OVERLAY_FLAG  --cache=$allocatesafe ${FreezerFlags} --datadir=/var/lib/ethereum --light.maxpeers 0 --maxpeers 25 ${ReplicaHTTPFlag} ${ReplicaGraphQLFlag} ${ReplicaWebsocketsFlag}'
TimeoutStopSec=90
TimeoutStartSec=86400
RestartSec=10s
[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/geth-fallback.service


printf "[Unit]
Description=Ethereum go client
After=syslog.target network.target

[Service]
User=geth
Group=geth
Environment=HOME=/var/lib/ethereum
EnvironmentFile=/etc/systemd/system/ethcattle-vars
Type=simple
LimitNOFILE=655360
ExecStartPre=/usr/bin/bash -c '/usr/bin/geth replica --snapshot=false --cache=$allocatesafe ${ReplicaExtraFlags} ${FreezerFlags} --kafka.broker=$KAFKA_ESCAPED_URL""$SEP_ESCAPED""fetch.default=8388608\\&max.waittime=25\\&avoid_leader=1  --datadir=/var/lib/ethereum --kafka.topic=${KafkaTopic} --replica.syncshutdown 2>>/tmp/geth-stderr'
ExecStart=/usr/bin/geth ${MasterExtraFlags} ${FreezerFlags} --rpc.allow-unprotected-txs --snapshot=false --txlookuplimit=0 --light.maxpeers 0 --maxpeers 25 --gcmode=archive --kafka.broker=${KafkaBrokerURL}""$SEP""net.maxopenrequests=1\&message.send.max.retries=20000  --datadir=/var/lib/ethereum --kafka.topic=${KafkaTopic} --kafka.txpool.topic=${InfrastructureStack}-txpool ${EventsTopicFlag}
TimeoutStartSec=86400
TimeoutStopSec=90
OnFailure=poweroff.target

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/geth-master.service

printf "[Unit]
Description=Ethereum go client
After=syslog.target network.target

[Service]
User=geth
Group=geth
Environment=HOME=/var/lib/ethereum
EnvironmentFile=/etc/systemd/system/ethcattle-vars
Type=simple
LimitNOFILE=655360
ExecStartPre=/usr/bin/bash -c '/usr/bin/geth replica --snapshot=false --cache=$allocatesafe ${ReplicaExtraFlags} ${FreezerFlags} $OVERLAY_FLAG --kafka.broker=$KAFKA_ESCAPED_URL""$SEP_ESCAPED""fetch.default=8388608\\&max.waittime=25\\&avoid_leader=1  --datadir=/var/lib/ethereum --kafka.topic=${KafkaTopic} --replica.syncshutdown 2>>/tmp/geth-stderr'
ExecStart=/usr/bin/geth ${MasterExtraFlags} ${FreezerFlags} $OVERLAY_FLAG --rpc.allow-unprotected-txs --snapshot=false --txlookuplimit=0 --light.maxpeers 0 --maxpeers 25 --gcmode=archive --kafka.broker=${KafkaBrokerURL}""$SEP""net.maxopenrequests=1\&message.send.max.retries=20000  --datadir=/var/lib/ethereum --kafka.topic=${KafkaTopic} --kafka.txpool.topic=${InfrastructureStack}-txpool ${EventsTopicFlag}
TimeoutStartSec=86400
TimeoutStopSec=90
OnFailure=poweroff.target

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/geth-master-overlay.service


printf "[Unit]
Description=Ethereum go client transaction relay
After=syslog.target network.target geth

[Service]
User=geth
Group=geth
Environment=HOME=/var/lib/ethereum
Type=simple
ExecStart=/usr/bin/geth txrelay --kafka.broker=${KafkaBrokerURL} --kafka.tx.topic=${NetworkId}-tx --kafka.tx.consumergroup=${KafkaTopic}-cg /var/lib/ethereum/geth.ipc
TimeoutStopSec=90
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/geth-tx.service

printf "[Unit]
Description=Geth Peer Monitoring
After=syslog.target network.target geth

[Service]
User=geth
Group=geth
Environment=HOME=/var/lib/ethereum
Type=simple
ExecStart=/usr/local/bin/peerManager.py /var/lib/ethereum/geth.ipc ${NetworkId}-peerlist ${KafkaBrokerURL}
KillMode=process
TimeoutStopSec=90
Restart=on-failure
RestartSec=10s
" > /etc/systemd/system/geth-peer-data.service
