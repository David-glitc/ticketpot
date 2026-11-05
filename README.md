# TicketPot

No-loss prize pool on BOT Chain, in native BOT. Stack: Foundry (Solidity 0.8.24, paris) + SolidJS / Vite.

## The gap
BOT Chain has no yield source (no lending market), so classic "prize-linked savings" cannot work. TicketPot flips it: **prizes come from
sponsors** (projects that want attention, communities, anyone), **depositors risk nothing**. Deposit BOT, hold tickets, withdraw any time, win the pot.
It is a distribution tool for ecosystem projects: sponsor the pot and every depositor sees you.

## Contract surface (`src/TicketPot.sol`, no owner, no admin, no upgrades)
| Function | What |
|---|---|
| `deposit()` | Add principal (min 0.01 BOT). Counts in the draw from the **next round**. |
| `withdraw(amount)` | Take principal back. **Always works**, including during a draw. |
| `sponsor()` | Add to the prize pot. 5% fee to the immutable treasury. Plain transfers to the contract are fee-free donations. |
| `sync(address[])` | Permissionless: moves last round's deposits into the draw and applies deferred exits. |
| `commitDraw(hash)` / `revealDraw(secret)` / `slashCommit()` | Weekly draw, see below. |
| `claim()` | Pull prizes, keeper rewards and fees. |

## The draw
1. After a round ends (plus a grace of roundLength/24 so keepers can `sync` everyone), anyone calls `commitDraw(keccak(secret, self))` with a bond of max(0.05 BOT, 10% of the pot). The tree of weights is **frozen**.
2. Ten blocks later the seed is `keccak(secret, blockhash(commitBlock+10))`. The committer reveals within 200 blocks (about 3 minutes; the UI/keeper does it) and gets the bond back plus 1% of the pot. Winner takes 99%, chosen by weight (Fenwick-tree sortition, O(log n)).
3. Missed reveal: anyone `slashCommit()` - the bond joins the pot and anyone can commit again.

## Main risks and how they are handled
| Risk | Handling |
|---|---|
| Deposit right before the draw, withdraw right after | New deposits only count from the next round. |
| Committer picks the winner | Needs a secret and an unknown future blockhash: at commit nobody knows the outcome. |
| Committer **aborts** after seeing the result | The only real bias: abort when losing, to retry. Costs the bond (>=10% of the pot) every time, and the bond grows the pot. A rational attacker needs a share large enough that the retry value beats the bond. For small pots raise the minimum bond. |
| Validator manipulates the blockhash | BOT Chain has a small validator set; a validator that is also the committer can grind. Residual trust assumption, same class as any blockhash-seeded draw. Fine for prizes of this size; upgrade path is a VRF once one exists on chain. |
| Withdraw during the lock changes the winner | Tree is frozen; exits are recorded as `pendingCut` and applied after the reveal. The winner keeps the prize even if they exit; next commit is blocked until cuts are applied (`sync`, permissionless). |
| Principal is at risk | No external calls except sending BOT, no admin, no borrowing. Invariant tests: balance >= principal + pot + owed + bonds, and principal accounting is exact. |
| Slot cap | 65,535 distinct depositors (slots are not recycled). |
| Unsynced deposits miss a draw | Principal unaffected; they count next time. The keeper panel has "Sync all players". |

## Fees
5% of sponsored prizes to the treasury. Nothing is ever taken from principal.

## Run it
```bash
forge test                                                    # 15 unit/fuzz + 3 invariant tests
forge test --match-contract Fork --fork-url https://rpc.botchain.ai   # read-only draw rehearsal on BOT Chain mainnet fork (chain 677)
(cd web && npm install && npm test && npm run build)
bash script/local.sh && (cd web && npm run dev)                # anvil on chain 677 + deploy + seeded demo -> http://localhost:5174
```
(`lib/forge-std` is not committed: `forge install foundry-rs/forge-std --no-git` after cloning.) BDEX is not used, so the fork test checks the draw on live-chain settings.
