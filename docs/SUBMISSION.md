# Submission Packet — Reactive Omni Buildathon (DRAFT, pending funding + deploy)

Track: **Set It and Forget It** · Project: **Payday Splitter**
Deadline (planning assumption, verified): **5 Dec 2026 20:00 UTC = 6 Dec 03:00 WIB**
Event page: https://dorahacks.io/hackathon/reactive-omni-buildathon/detail

## Checklist (DoraHacks submit form)

- [x] Public repo: https://github.com/backburner036-prog/payday-splitter
- [ ] Deployed contract addresses (fill after `script/deploy.sh`)
  - PaydaySplitter (Unichain Sepolia 1301): TBD
  - PaydayReactive (Reactive Lasna 5318007): TBD
- [ ] Tx hashes, full loop (fill after `script/demo.sh` → `demo-log.json`)
  - `plan_tx` (setPlan): TBD
  - `payday_tx` (origin event): TBD
  - reactive tx on Lasna (react): TBD — find via https://lasna.reactscan.net
    (filter txs to the PaydayReactive address, match `splitsRequested` increment)
  - `callback_split_tx` (PaydaySplit event): TBD
- [ ] Demo video < 3 min: `docs/demo.mp4` (record after live loop works)

## Funding blocker (single item — needs coordinator/IDR)

Deployer (fresh, testnet-only, this hackathon only):
`0xB3D3F5De669E6a1d5bF64C111F8f99B4D0527edB` — balance 0 on all chains.

Needs **~0.15 Sepolia ETH** (free testnet funds, no KYC):
- ~0.05 ETH → bridge to Unichain Sepolia (splitter deploy + 0.02 ETH
  callback float + demo paydays). Bridge: Unichain bridge UI, or Superbridge.
- ~0.10 ETH → send to Reactive faucet `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`
  (1 ETH → 100 lREACT) = 10 lREACT for the Lasna deploy (2 lREACT at deploy)
  + reactive contract funding.
Fastest path: IDR/coordinator claims Sepolia ETH from the Alchemy faucet
in a browser (1 min, free) and sends 0.15 ETH to the deployer above.
PoW faucet (sepolia-faucet.pk910.de) was evaluated and rejected: browser
WASM mining on this VM is uneconomical for the amount needed.

Once funded, run (est. 30–45 min):
```bash
cd ~/workspace/hackathon/reactive-omni-20261123/payday-splitter
bash script/deploy.sh   # deploys + wires + funds; writes deployments.json
bash script/demo.sh 0.05  # full loop; writes demo-log.json
# record docs/demo.mp4 (shot list below), fill this packet, submit on DoraHacks
```

## Demo video — shot list (< 3 min)

1. (0:00–0:20) Title card + one-line pitch; repo link on screen.
2. (0:20–0:50) `setPlan` + `payday()` in terminal (cast send), show payday tx
   hash; Unichain Sepolia explorer showing `PaydayReceived` event.
3. (0:50–1:40) Lasna explorer (https://lasna.reactscan.net) — reactive
   contract, `react()` tx, `SplitRequested` event; `splitsRequested = 1`.
4. (1:40–2:30) Unichain explorer — callback `splitPayday` tx, `PaydaySplit`
   event; beneficiary balances before/after (50/30/20).
5. (2:30–2:55) Code walk-through (30 s): `react()` → `requestCallbackV_1_0`
   → `splitPayday()` auth; tests `forge test` 19/19.
6. (2:55–3:00) End card: repo + contract addresses + track.

Recording: headless Chromium screenshots of the two explorers + terminal
captures, assembled with ffmpeg (no voiceover needed; captions on screen).

## KYC/R9 status (for the record — NOT a blocker)

Perintah IDR 23 Nov 09:47 WIB: jeda dicabut, eksekusi lanjut; pertanyaan
verdict R9 (apakah klausul template DoraHacks mengatur event ini) tidak lagi
jadi blocker. Status klausul, dicatat di sini:
- Halaman event + DoraHacks ToS (9 Okt 2023): TIDAK ada klausul KYC.
- Template T&C organizer dashboard DoraHacks: klausul "4. Prize distribution
  is subject to KYC/AML review and sponsor approval where applicable."
  (URL mengandung `$demo` — template/demo, bukan T&C spesifik event ini).
- Bila menang dan payout menuntut dokumen identitas, keputusan milik IDR;
  lane TIDAK PERNAH mengisi/mengirim dokumen identitas atau form pajak.
