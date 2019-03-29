#!/bin/bash
while true; do
  printf "peerCount: "
  echo '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":64}' | nc -U /var/lib/ethereum/geth.ipc | jq -cr '"ibase=16;obase=A;" + (.result | ltrimstr("0x") | ascii_upcase)' | bc
  sleep 30
done
