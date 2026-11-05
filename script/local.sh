#!/usr/bin/env bash
# Local demo: anvil (chain 677, 1h rounds) + deploy + a couple of depositors and a sponsor. Uses anvil's public dev keys only.
set -euo pipefail
cd "$(dirname "$0")/.."
K0=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
K1=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
K2=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
RPC=http://127.0.0.1:8545
anvil --chain-id 677 --block-time 1 >/dev/null 2>&1 & echo $! > .anvil.pid
sleep 2
OUT=$(TREASURY=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 ROUND_LENGTH=3600 forge script script/Deploy.s.sol --rpc-url $RPC --private-key $K0 --broadcast 2>&1)
ADDR=$(echo "$OUT" | grep -o 'TicketPot 0x[0-9a-fA-F]*' | awk '{print $2}')
mkdir -p web/public; echo "{\"address\":\"$ADDR\",\"chainId\":677,\"rpc\":\"$RPC\",\"roundLength\":3600}" > web/public/deployment.json
cast send $ADDR "deposit()" --value 25ether --private-key $K1 --rpc-url $RPC >/dev/null
cast send $ADDR "deposit()" --value 10ether --private-key $K2 --rpc-url $RPC >/dev/null
cast send $ADDR "sponsor()" --value 20ether --private-key $K0 --rpc-url $RPC >/dev/null
echo "TicketPot at $ADDR ; anvil pid $(cat .anvil.pid) ; run: cd web && npm run dev"
