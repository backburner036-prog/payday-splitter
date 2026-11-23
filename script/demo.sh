#!/usr/bin/env bash
# Payday Splitter — full-loop demo driver (testnet).
# Runs the loop end to end and records every tx hash for the submission:
#   setPlan -> payday() [Unichain Sepolia] -> react() [Lasna]
#   -> splitPayday callback [Unichain Sepolia] -> 3 beneficiary transfers.
# Usage: ./script/demo.sh [amount-eth, default 0.05]
set -euo pipefail

export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source .env
: "${DEPLOYER_PK:?set DEPLOYER_PK in .env}"
: "${DEPLOYER_ADDR:?set DEPLOYER_ADDR in .env}"

UNI_RPC="https://sepolia.unichain.org"
LASNA_RPC="https://lasna-rpc.rnk.dev/"
AMOUNT="${1:-0.05}"

SPLITTER=$(jq -r '.contracts.PaydaySplitter' deployments.json)
REACTIVE=$(jq -r '.contracts.PaydayReactive' deployments.json)
echo "Splitter: $SPLITTER"
echo "Reactive: $REACTIVE"

# Three distinct beneficiaries (fresh addresses; keys never needed — receive-only).
BEN2=$(cast wallet new 2>/dev/null | grep -o '0x[0-9a-fA-F]\{40\}' | head -1)
BEN3=$(cast wallet new 2>/dev/null | grep -o '0x[0-9a-fA-F]\{40\}' | head -1)
echo "Beneficiaries: savings=$DEPLOYER_ADDR bills=$BEN2 fun=$BEN3"

echo "== 1. setPlan (50/30/20) =="
PLAN_TX=$(cast send "$SPLITTER" "setPlan(address,address,address,uint16,uint16,uint16)" \
  "$DEPLOYER_ADDR" "$BEN2" "$BEN3" 5000 3000 2000 \
  --rpc-url "$UNI_RPC" --private-key "$DEPLOYER_PK" --json | jq -r '.transactionHash')
echo "plan tx: $PLAN_TX"

echo "== 2. payday($AMOUNT ETH) =="
PAYDAY_TX=$(cast send "$SPLITTER" "payday()" --value "${AMOUNT}ether" \
  --rpc-url "$UNI_RPC" --private-key "$DEPLOYER_PK" --json | jq -r '.transactionHash')
echo "payday tx: $PAYDAY_TX"
PAYDAY_BLOCK=$(cast tx "$PAYDAY_TX" --rpc-url "$UNI_RPC" --json | jq -r '.blockNumber')

echo "== 3. Wait for reactive + callback (poll up to 5 min) =="
SPLIT_TX=""
for i in $(seq 1 60); do
  SPLITS=$(cast call "$SPLITTER" "totalSplits()" --rpc-url "$UNI_RPC")
  REQ=$(cast call "$REACTIVE" "splitsRequested()" --rpc-url "$LASNA_RPC")
  echo "  t+${i}x5s splitsRequested=$REQ totalSplits=$SPLITS"
  if [ "$SPLITS" != "0" ]; then break; fi
  sleep 5
done

echo "== 4. Find the callback delivery tx (PaydaySplit event) =="
SPLIT_TX=$(cast logs --from-block "$PAYDAY_BLOCK" --to-block latest \
  --address "$SPLITTER" \
  "PaydaySplit(address,uint256,uint256,uint256,uint256,uint256)" \
  --rpc-url "$UNI_RPC" --json 2>/dev/null | jq -r '.[0].transactionHash // empty')
echo "callback/split tx: ${SPLIT_TX:-NOT FOUND (check manually)}"

echo "== 5. Final balances =="
echo "savings ($DEPLOYER_ADDR): $(cast balance "$DEPLOYER_ADDR" --rpc-url "$UNI_RPC")"
echo "bills   ($BEN2): $(cast balance "$BEN2" --rpc-url "$UNI_RPC")"
echo "fun     ($BEN3): $(cast balance "$BEN3" --rpc-url "$UNI_RPC")"
echo "pending: $(cast call "$SPLITTER" "pending(address)(uint256)" "$DEPLOYER_ADDR" --rpc-url "$UNI_RPC")"
echo "totalSplit: $(cast call "$SPLITTER" "totalSplit()" --rpc-url "$UNI_RPC")"

cat > demo-log.json <<EOF
{
  "plan_tx": "$PLAN_TX",
  "payday_tx": "$PAYDAY_TX",
  "payday_block": "$PAYDAY_BLOCK",
  "callback_split_tx": "${SPLIT_TX:-}",
  "splitter": "$SPLITTER",
  "reactive": "$REACTIVE",
  "beneficiaries": {
    "savings": "$DEPLOYER_ADDR",
    "bills": "$BEN2",
    "fun": "$BEN3"
  },
  "amount_eth": "$AMOUNT"
}
EOF
echo "== demo-log.json written =="
