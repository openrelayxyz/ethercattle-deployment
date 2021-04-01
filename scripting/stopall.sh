#!/bin/bash -xe

systemctl stop amazon-cloudwatch-agent.service || true &
systemctl stop geth-fallback.service || true &
systemctl stop geth-master-overlay.service  || true &
systemctl stop geth-master.service  || true &
systemctl stop geth-peer-data.service || true &
systemctl stop geth-replica.service || true &
systemctl stop geth-tx.service || true &
systemctl stop journald-cloudwatch-logs || true &
wait
