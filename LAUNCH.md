# TicketPot launch (needs the owner's approval - nothing here has run on mainnet)

Gas (Foundry gas report; ~22 gwei assumed from wave 3's "5M gas ~ 0.11 BOT"):
| Action | Gas | ~BOT |
|---|---|---|
| Deploy | ~1.35M | 0.030 |
| deposit | 120-140k | 0.003 |
| withdraw | ~120k | 0.0026 |
| sponsor | ~90k | 0.002 |
| commitDraw + revealDraw | ~165k + ~160k | 0.007 |
| sync (per batch of ~10 users) | ~500k | 0.011 |

Steps
1. Choose `TREASURY` and ROUND_LENGTH (7 days default).
2. Fresh deployer with ~0.1 BOT (not a wave 1 key). `TREASURY=0x.. forge script script/Deploy.s.sol --rpc-url https://rpc.botchain.ai --broadcast --private-key $KEY`
3. Verify on BOTScan. Seed the first pot (sponsor 1-5 BOT, ideally from a partner), deposit 0.1 BOT from a second wallet.
4. Run a 1-hour-round rehearsal deployment first (ROUND_LENGTH=3600) to test commit/reveal with a real keeper before the weekly one.
5. Static site: `cd web && npm run build`, add `deployment.json` ({address, chainId:677, rpc, roundLength}) to `dist/`, host (needs approval).

Open decisions: treasury address; first sponsor; whether to raise MIN_BOND for small pots; round length.
