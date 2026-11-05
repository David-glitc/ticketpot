import { render } from "solid-js/web";
import { createSignal, createResource, onCleanup, Show, For } from "solid-js";
import { BrowserProvider, JsonRpcProvider, Contract, formatEther, parseEther, keccak256, AbiCoder, hexlify, randomBytes } from "ethers";
import { countdown, winChance, winnerPrize, drawStep } from "./lib.js";
import "./style.css";

const ABI = [
  "function pot() view returns (uint256)", "function treeTotal() view returns (uint256)", "function totalPrincipal() view returns (uint256)",
  "function totalPendingCut() view returns (uint256)", "function locked() view returns (bool)", "function drawCount() view returns (uint256)",
  "function nextDrawTime() view returns (uint256)", "function bondRequired() view returns (uint256)", "function userCount() view returns (uint256)",
  "function commitment() view returns (address committer, bytes32 hash, uint64 block, uint64 round, uint256 bond, uint256 prize)",
  "function users(address) view returns (uint16 slot,uint64 freshRound,uint256 eligible,uint256 fresh,uint256 pendingCut)",
  "function owed(address) view returns (uint256)", "function slotOwner(uint256) view returns (address)",
  "function deposit() payable", "function withdraw(uint256)", "function sponsor() payable", "function claim()",
  "function sync(address[])", "function commitDraw(bytes32) payable", "function revealDraw(bytes32)", "function slashCommit()",
  "event DrawResult(uint256 indexed draw, address indexed winner, uint256 prize, uint256 keeperReward)",
];
const f = (w) => Number(formatEther(w)).toLocaleString(undefined, { maximumFractionDigits: 4 });
const EXPLORER = "https://scan.botchain.ai";
const coder = AbiCoder.defaultAbiCoder();

function App() {
  const [cfg] = createResource(() => fetch("/deployment.json").then((r) => r.json()).catch(() => null));
  const [err, setErr] = createSignal(""); const [acct, setAcct] = createSignal(""); const [busy, setBusy] = createSignal(false);
  const [amt, setAmt] = createSignal("1"); const [now, setNow] = createSignal(Math.floor(Date.now() / 1000));
  const [tick, setTick] = createSignal(0); let rw;
  const t = setInterval(() => { setNow(Math.floor(Date.now() / 1000)); if (Date.now() % 5 < 1) setTick((x) => x + 1); }, 1000); onCleanup(() => clearInterval(t));
  setInterval(() => setTick((x) => x + 1), 4000);

  const [s] = createResource(() => [cfg(), acct(), tick()], async ([c, a]) => {
    if (!c) return null;
    const p = new JsonRpcProvider(c.rpc); const k = new Contract(c.address, ABI, p);
    const [pot, tree, principal, cut, locked, draws, next, bond, nUsers, cm, block] = await Promise.all([k.pot(), k.treeTotal(), k.totalPrincipal(), k.totalPendingCut(), k.locked(), k.drawCount(), k.nextDrawTime(), k.bondRequired(), k.userCount(), k.commitment(), p.getBlockNumber()]);
    const me = a ? { u: await k.users(a), owed: await k.owed(a) } : null;
    const logs = await k.queryFilter(k.filters.DrawResult(), Math.max(0, block - 50000));
    return { pot, tree, principal, cut, locked, draws, next: Number(next), bond, nUsers: Number(nUsers), cm, block, me, logs, k };
  });
  async function connect() {
    try {
      let bp = new BrowserProvider(window.ethereum); await bp.send("eth_requestAccounts", []);
      if ((await bp.getNetwork()).chainId !== BigInt(cfg().chainId)) {
        const hex = "0x" + cfg().chainId.toString(16);
        try { await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: hex }] }); }
        catch (e) { if (e.code !== 4902 && e?.data?.originalError?.code !== 4902) throw e;
          await window.ethereum.request({ method: "wallet_addEthereumChain", params: [{ chainId: hex, chainName: "BOT Chain", nativeCurrency: { name: "BOT", symbol: "BOT", decimals: 18 }, rpcUrls: [cfg().rpc], blockExplorerUrls: [EXPLORER] }] }); }
        bp = new BrowserProvider(window.ethereum);
      }
      if ((await bp.getNetwork()).chainId !== BigInt(cfg().chainId)) throw new Error("Switch wallet to chain " + cfg().chainId);
      const sg = await bp.getSigner(); rw = new Contract(cfg().address, ABI, sg); setAcct(await sg.getAddress());
    } catch (e) { setErr(e.shortMessage || e.message); }
  }
  async function go(fn) { setErr(""); setBusy(true); try { await (await fn()).wait(); setTick((x) => x + 1); } catch (e) { setErr(e.shortMessage || e.message); } finally { setBusy(false); } }
  const secretKey = () => "ticketpot-secret-" + cfg().address;
  async function commit() {
    const secret = hexlify(randomBytes(32)); const h = keccak256(coder.encode(["bytes32", "address"], [secret, acct()]));
    try { localStorage.setItem(secretKey(), secret); } catch {}
    await go(() => rw.commitDraw(h, { value: s().bond }));
  }
  const reveal = () => go(() => rw.revealDraw(localStorage.getItem(secretKey())));
  const syncAll = async () => {
    const n = s().nUsers; const addrs = []; for (let i = 0; i < n; i++) addrs.push(await s().k.slotOwner(i));
    await go(() => rw.sync(addrs));
  };
  const step = () => s() && drawStep({ now: now(), nextDraw: s().next, locked: s().locked, commitBlock: Number(s().cm.block), block: s().block, pot: s().pot, treeTotal: s().tree, pendingCut: s().cut });

  return (
    <main>
      <header><h1>TicketPot</h1><Show when={!acct()} fallback={<span class="mut">{acct().slice(0, 8)}…</span>}><button onClick={connect}>Connect wallet</button></Show></header>
      <p class="mut">Deposit BOT, keep it. Weekly draw, winner takes the prize pot funded by sponsors. Withdraw your deposit any time.</p>
      <Show when={cfg() && cfg().launched && cfg().chainId === 677 && /^https:/.test(cfg().rpc)}>
        <aside class="launch" aria-label="Launch announcement"><b>Officially launched on BOT Chain Mainnet</b>
          <span class="mut">{cfg().launched} · TicketPot <a href={EXPLORER + "/address/" + cfg().address} target="_blank" rel="noopener noreferrer">{cfg().address}</a> · {cfg().roundLength / 86400}-day rounds</span></aside>
      </Show>
      <Show when={err()}><p class="err">{err()}</p></Show>
      <Show when={s()} fallback={<p class="mut">{cfg.loading ? "Loading…" : "No deployment.json found."}</p>}>
        <div class="grid">
          <div class="card"><div class="mut">Prize pot</div><div class="big">{f(s().pot)} BOT</div><div class="mut">winner gets {f(winnerPrize(s().pot))}</div></div>
          <div class="card"><div class="mut">Next draw</div><div class="big">{countdown(s().next - now())}</div><div class="mut">draw #{String(Number(s().draws) + 1)}</div></div>
          <div class="card"><div class="mut">Deposited</div><div class="big">{f(s().principal)} BOT</div><div class="mut">{s().nUsers} players</div></div>
        </div>
        <Show when={acct()}>
          <div class="card">
            <b>Your tickets</b>
            <div class="mut">Deposit {f(s().me.u.eligible + s().me.u.fresh)} BOT · counting in the next draw {f(s().me.u.eligible)} ({(winChance(s().me.u.eligible, s().tree) * 100).toFixed(2)}% chance) · new deposits count from the next round</div>
            <div class="row"><input value={amt()} onInput={(e) => setAmt(e.target.value)} /> BOT
              <button disabled={busy()} onClick={() => go(() => rw.deposit({ value: parseEther(amt()) }))}>Deposit</button>
              <button class="ghost" disabled={busy()} onClick={() => go(() => rw.withdraw(parseEther(amt())))}>Withdraw</button>
              <button class="ghost" disabled={busy()} onClick={() => go(() => rw.withdraw(s().me.u.eligible + s().me.u.fresh))}>Withdraw all</button>
              <button class="ghost" disabled={busy()} onClick={() => go(() => rw.sponsor({ value: parseEther(amt()) }))}>Sponsor pot (5% fee)</button></div>
            <Show when={s().me.owed > 0n}><div class="row">Prizes to claim: {f(s().me.owed)} BOT <button disabled={busy()} onClick={() => go(() => rw.claim())}>Claim</button></div></Show>
          </div>
          <div class="card">
            <b>Keeper</b> <span class="mut">anyone can run the draw; reveal returns your bond and pays 1% of the pot</span>
            <div class="row"><span class="tag">{step().label}</span>
              <Show when={step().key === "commit"}><button disabled={busy()} onClick={commit}>Commit (bond {f(s().bond)} BOT)</button></Show>
              <Show when={step().key === "reveal"}><button disabled={busy()} onClick={reveal}>Reveal</button></Show>
              <Show when={step().key === "slash"}><button disabled={busy()} onClick={() => go(() => rw.slashCommit())}>Slash</button></Show>
              <Show when={step().key !== "wait" && step().key !== "reveal"}><button class="ghost" disabled={busy()} onClick={syncAll}>Sync all players</button></Show></div>
          </div>
        </Show>
        <div class="card"><b>Past winners</b>
          <For each={[...s().logs].reverse()} fallback={<div class="mut">No draws yet.</div>}>{(l) => <div class="mut">#{String(l.args.draw)} · {l.args.winner.slice(0, 10)}… won {f(l.args.prize)} BOT</div>}</For></div>
      </Show>
    </main>
  );
}
render(() => <App />, document.getElementById("root"));
