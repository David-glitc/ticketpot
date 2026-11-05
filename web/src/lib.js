export const SPONSOR_FEE_BPS = 500n, KEEPER_BPS = 100n;
export function countdown(sec) {
  if (sec <= 0) return "now";
  const d = Math.floor(sec / 86400), h = Math.floor((sec % 86400) / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  return d ? `${d}d ${h}h` : h ? `${h}h ${m}m` : `${m}m ${s}s`;
}
/** Chance (0..1) that a depositor with `weight` wins, given tree total. */
export function winChance(weight, total) { const w = BigInt(weight), t = BigInt(total); return t === 0n ? 0 : Number((w * 1000000n) / t) / 1e6; }
/** Prize the winner receives from a pot (after keeper reward). */
export function winnerPrize(pot) { return BigInt(pot) - (BigInt(pot) * KEEPER_BPS) / 10000n; }
/** Net prize after the sponsor fee for an amount a sponsor sends. */
export function sponsorNet(amount) { return BigInt(amount) - (BigInt(amount) * SPONSOR_FEE_BPS) / 10000n; }
/** Draw state machine for the keeper panel. */
export function drawStep({ now, nextDraw, locked, commitBlock, block, pot, treeTotal, pendingCut }) {
  if (locked) {
    if (block <= commitBlock + 10) return { key: "wait", label: `Waiting ${commitBlock + 11 - block} more blocks` };
    if (block > commitBlock + 200) return { key: "slash", label: "Reveal window missed - slash the bond" };
    return { key: "reveal", label: "Ready to reveal" };
  }
  if (now < nextDraw) return { key: "early", label: "Next draw in " + countdown(nextDraw - now) };
  if (pendingCut > 0n) return { key: "cuts", label: "Apply pending exits first (sync)" };
  if (pot === 0n || treeTotal === 0n) return { key: "empty", label: "Needs prizes and eligible deposits" };
  return { key: "commit", label: "Ready to commit" };
}
