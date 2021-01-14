#!/usr/bin/env bash

set -e
set -x

# mke sure that geth is able to start as a full node and catch up with peers
sudo -Eu geth /usr/bin/geth ${MasterExtraFlags} --cache=$allocatesafe --light.maxpeers 0 --maxpeers 25 --rpc --rpcaddr 0.0.0.0 --rpcport 8545 --datadir=/var/lib/ethereum ${FreezerFlags} &
pid=$!
test_pass=0
while [ $test_pass -le 1 ]
do
  if curl -X POST --insecure -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":64}' localhost:8545
  then
    test_pass=$(( $test_pass + 1 ))
  else
    test_pass=0
  fi
  sleep 10
done
START_BLOCK=$(curl -X POST --insecure -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":64}' localhost:8545 | jq -r '.result')
END_BLOCK=$(curl -X POST --insecure -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":64}' localhost:8545 | jq -r '.result')
while [[ "$((END_BLOCK-START_BLOCK))" -lt "10" ]]; do
  END_BLOCK=$(curl -X POST --insecure -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":64}' localhost:8545 | jq -r '.result')
  sleep 10
done

kill -HUP $pid
