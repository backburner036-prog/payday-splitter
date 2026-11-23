#!/usr/bin/env bash
# Payday Splitter — testnet deploy script.
# Chain plan: PaydaySplitter on Unichain Sepolia (1301), PaydayReactive on
# Reactive Lasna (5318007). `forge script` CANNOT deploy the reactive
# contract (its constructor calls the system contract, which reverts in
# local simulation), so both deploys go out as raw creation transactions
# via `cast send --create` (pattern from Lambda's DEPLOY_TESTNET.md).
#
# Prereqs: .env with DEPLOYER_PK + DEPLOYER_ADDR (mode 600, never committed).
# Funding needed before running:
#   - Sepolia ETH on $DEPLOYER_ADDR (faucet) -> bridged to Unichain Sepolia
#     for the splitter deploy + demo, and -> lREACT for the Lasna deploy.
#   - lREACT: send Sepolia ETH to 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434
#     (1 ETH -> 100 lREACT, max 5 ETH/tx) or call request(address) with 0.1 ETH.
set -euo pipefail

export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")"

# shellcheck disable=SC1091
source .env
: "${DEPLOYER_PK:?set DEPLOYER_PK in .env}"
: "${DEPLOYER_ADDR:?set DEPLOYER_ADDR in .env}"

UNI_RPC="https://sepolia.unichain.org"
LASNA_RPC="https://lasna-rpc.rnk.dev/"
UNI_CHAIN=1301
LASNA_CHAIN=5318007
CALLBACK_PROXY="0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4" # Unichain Sepolia
TOPIC0="0x026ea514fc5e4e223bbdaf9d66e602619ec85302d4740f05480dc01bb7eec65c" # PaydayReceived
CALLBACK_GAS_LIMIT=500000
MIN_PAYDAY_WEI=1000000000000000 # 0.001 ether

forge build --quiet

echo "== balances =="
echo "Unichain Sepolia: $(cast balance "$DEPLOYER_ADDR" --rpc-url "$UNI_RPC") wei"
echo "Lasna lREACT:     $(cast balance "$DEPLOYER_ADDR" --rpc-url "$LASNA_RPC") wei"

echo "== 1. Deploy PaydaySplitter on Unichain Sepolia =="
SPLITTER_BYTECODE=$(jq -r '.bytecode.object' out/PaydaySplitter.sol/PaydaySplitter.json)
SPLITTER_ARGS=$(cast abi-encode "constructor(address)" "$CALLBACK_PROXY")
SPLITTER_TX=$(cast send --create "${SPLITTER_BYTECODE}${SPLITTER_ARGS:2}" \
  --rpc-url "$UNI_RPC" --private-key "$DEPLOYER_PK" --json)
SPLITTER=$(echo "$SPLITTER_TX" | jq -r '.contractAddress')
echo "PaydaySplitter: $SPLITTER"
echo "deploy tx: $(echo "$SPLITTER_TX" | jq -r '.transactionHash')"

echo "== 2. Deploy PaydayReactive on Lasna (funded with 2 lREACT) =="
REACTIVE_BYTECODE=$(jq -r '.bytecode.object' out/PaydayReactive.sol/PaydayReactive.json)
REACTIVE_ARGS=$(cast abi-encode "constructor(uint256,address,uint256,uint256,address,uint64,uint256)" \
  "$UNI_CHAIN" "$SPLITTER" "$TOPIC0" "$UNI_CHAIN" "$SPLITTER" "$CALLBACK_GAS_LIMIT" "$MIN_PAYDAY_WEI")
REACTIVE_TX=$(cast send --create "${REACTIVE_BYTECODE}${REACTIVE_ARGS:2}" \
  --value 2ether --rpc-url "$LASNA_RPC" --private-key "$DEPLOYER_PK" --json)
REACTIVE=$(echo "$REACTIVE_TX" | jq -r '.contractAddress')
echo "PaydayReactive: $REACTIVE"
echo "deploy tx: $(echo "$REACTIVE_TX" | jq -r '.transactionHash')"

echo "== 3. Wire splitter -> reactive =="
cast send "$SPLITTER" "setReactive(address)" "$REACTIVE" \
  --rpc-url "$UNI_RPC" --private-key "$DEPLOYER_PK" --json | jq -r '.transactionHash'

echo "== 4. Fund splitter with 0.02 ETH (callback-gas float, destination side) =="
cast send "$SPLITTER" --value 0.02ether \
  --rpc-url "$UNI_RPC" --private-key "$DEPLOYER_PK" --json | jq -r '.transactionHash'

cat > deployments.json <<EOF
{
  "network": {
    "origin_chain_id": $UNI_CHAIN,
    "origin_rpc": "$UNI_RPC",
    "lasna_chain_id": $LASNA_CHAIN,
    "lasna_rpc": "$LASNA_RPC",
    "callback_proxy_unichain_sepolia": "$CALLBACK_PROXY",
    "payday_received_topic0": "$TOPIC0"
  },
  "contracts": {
    "PaydaySplitter": "$SPLITTER",
    "PaydayReactive": "$REACTIVE"
  },
  "deployer": "$DEPLOYER_ADDR"
}
EOF
echo "== deployments.json written =="
cat deployments.json
