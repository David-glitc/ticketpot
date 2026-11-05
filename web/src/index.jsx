import { render } from "solid-js/web";
import { createSignal, createResource, onCleanup, Show, For } from "solid-js";
import { BrowserProvider, JsonRpcProvider, Contract, formatEther, parseEther, keccak256, AbiCoder, hexlify, randomBytes } from "ethers";
import { countdown, winChance, winnerPrize, drawStep } from "./lib.js";
import "@fontsource/fredoka/600.css";
import "@fontsource/fredoka/700.css";
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
  const t2 = setInterval(() => setTick((x) => x + 1), 4000); onCleanup(() => clearInterval(t2));

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

  const R = 150, C = 2 * Math.PI * R;
  const left = () => (s() ? Math.max(0, s().next - now()) : 0);
  const round = () => (cfg() && cfg().roundLength) || 604800;
  const frac = () => (s() ? Math.min(1, left() / round()) : 0);
  const dhm = () => { const l = left(); return [Math.floor(l / 86400), Math.floor((l % 86400) / 3600), Math.floor((l % 3600) / 60)]; };
  const mine = () => (s() && s().me ? s().me.u.eligible + s().me.u.fresh : 0n);
  const Stub = (p) => (<div class="stub"><div class="stub-k">{p.k}</div><div class="stub-v">{p.v}</div><div class="stub-s">{p.s}</div></div>);

  return (
    <main>
      <header class="top"><div class="logo"><svg width="28" height="28" viewBox="0 0 32 32" aria-hidden="true"><path d="M3 9a3 3 0 0 0 3-3h20a3 3 0 0 0 3 3v4a3 3 0 0 0 0 6v4a3 3 0 0 0-3 3H6a3 3 0 0 0-3-3v-4a3 3 0 0 0 0-6z" fill="#ffc93c" transform="translate(0 -1)"/><circle cx="16" cy="16" r="4" fill="#2a0f5c"/></svg>TicketPot</div>
        <Show when={!acct()} fallback={<span class="chip" title={acct()}>{acct().slice(0, 6)}…{acct().slice(-4)}</span>}><button class="btn pop" onClick={connect}>Connect wallet</button></Show></header>
      <Show when={cfg() && cfg().launched && cfg().chainId === 677 && /^https:/.test(cfg().rpc)}>
        <aside class="launch" aria-label="Launch announcement"><b>Officially launched on BOT Chain Mainnet</b>
          <span>{cfg().launched} · TicketPot <a href={EXPLORER + "/address/" + cfg().address} target="_blank" rel="noopener noreferrer">{cfg().address}</a> · {cfg().roundLength / 86400}-day rounds</span></aside>
      </Show>
      <Show when={err()}><p class="err" role="alert">{err()}</p></Show>

      <section class="hero" aria-label="Next draw">
        <div class="eyebrow">Weekly draw{s() ? " · Draw #" + String(Number(s().draws) + 1) : ""}</div>
        <div class="ring" role="timer" aria-label={s() ? `Next draw in ${dhm()[0]} days, ${dhm()[1]} hours, ${dhm()[2]} minutes` : "Loading next draw"}>
          <svg viewBox="0 0 340 340" aria-hidden="true"><circle class="trk" cx="170" cy="170" r={R} /><circle class="arc" cx="170" cy="170" r={R} stroke-dasharray={C} stroke-dashoffset={C * (1 - frac())} transform="rotate(-90 170 170)" /></svg>
          <div class="ring-in">
            <div class="pot-l">Prize pot</div>
            <div class="pot">{s() ? f(s().pot) : "…"}<small> BOT</small></div>
            <div class="pot-s">{s() ? "winner gets " + f(winnerPrize(s().pot)) : cfg.loading ? "Loading…" : "No deployment.json found."}</div>
            <div class="dhm"><span><b>{s() ? dhm()[0] : "–"}</b>d</span><span><b>{s() ? dhm()[1] : "–"}</b>h</span><span><b>{s() ? dhm()[2] : "–"}</b>m</span></div>
            <Show when={s() && left() === 0}><div class="due">Draw is due</div></Show>
          </div>
        </div>
        <p class="tag-line">Deposit BOT, keep it. Win the pot.</p>
        <p class="safe"><span aria-hidden="true">✓</span> Your principal is always withdrawable. Prizes come from sponsors, never from your deposit.</p>
      </section>

      <Show when={s()}>
        <section class="stubs" aria-label="Round stats">
          <Stub k="Your deposit" v={acct() ? f(mine()) + " BOT" : "–"} s={acct() ? (winChance(s().me.u.eligible, s().tree) * 100).toFixed(2) + "% win chance" : "Connect to see"} />
          <Stub k="Players" v={String(s().nUsers)} s={f(s().principal) + " BOT in the pool"} />
          <Stub k="Draw #" v={String(Number(s().draws) + 1)} s={Number(s().draws) + " drawn so far"} />
        </section>
      </Show>

      <section class="panel" aria-label="Deposit and withdraw">
        <div class="panel-main">
          <h2>Your ticket</h2>
          <Show when={acct() && s()} fallback={<div><p class="lead">Connect your wallet to deposit, withdraw or sponsor the pot.</p><button class="btn pop" onClick={connect}>Connect wallet</button></div>}>
            <p class="lead">Deposit {f(mine())} BOT · counting in the next draw {f(s().me.u.eligible)}. New deposits count from the next round.</p>
            <label class="amt">Amount<span><input inputmode="decimal" value={amt()} onInput={(e) => setAmt(e.target.value)} /> BOT</span></label>
            <div class="row">
              <button class="btn pop" disabled={busy()} onClick={() => go(() => rw.deposit({ value: parseEther(amt()) }))}>Deposit</button>
              <button class="btn ghost" disabled={busy()} onClick={() => go(() => rw.withdraw(parseEther(amt())))}>Withdraw</button>
              <button class="btn ghost" disabled={busy()} onClick={() => go(() => rw.withdraw(s().me.u.eligible + s().me.u.fresh))}>Withdraw all</button>
              <button class="btn ghost" disabled={busy()} onClick={() => go(() => rw.sponsor({ value: parseEther(amt()) }))}>Sponsor pot (5% fee)</button></div>
            <Show when={s().me.owed > 0n}><div class="row claim">Prizes to claim: <b>{f(s().me.owed)} BOT</b> <button class="btn gold" disabled={busy()} onClick={() => go(() => rw.claim())}>Claim</button></div></Show>
          </Show>
        </div>
        <div class="panel-stub" aria-hidden="false"><div class="stub-k">Always yours</div><div class="seal">100%</div><div class="stub-s">of your principal can be withdrawn at any time</div></div>
      </section>

      <Show when={acct() && s()}>
        <section class="keeper" aria-label="Keeper">
          <b>Keeper desk</b> <span class="mut">anyone can run the draw; reveal returns your bond and pays 1% of the pot</span>
          <div class="row"><span class="tag">{step().label}</span>
            <Show when={step().key === "commit"}><button class="btn pop" disabled={busy()} onClick={commit}>Commit (bond {f(s().bond)} BOT)</button></Show>
            <Show when={step().key === "reveal"}><button class="btn pop" disabled={busy()} onClick={reveal}>Reveal</button></Show>
            <Show when={step().key === "slash"}><button class="btn pop" disabled={busy()} onClick={() => go(() => rw.slashCommit())}>Slash</button></Show>
            <Show when={step().key !== "wait" && step().key !== "reveal"}><button class="btn ghost" disabled={busy()} onClick={syncAll}>Sync all players</button></Show></div>
        </section>
      </Show>

      <section class="fair" aria-labelledby="fair-h">
        <h2 id="fair-h">How the draw is fair</h2>
        <ol class="steps">
          <li><span class="n">1</span><b>Commit</b><span>A keeper locks a hidden secret and posts a bond. Nobody, the keeper included, can change it.</span></li>
          <li><span class="n">2</span><b>Reveal</b><span>Ten blocks later the secret is revealed and mixed with a block hash nobody knew at commit time.</span></li>
          <li><span class="n">3</span><b>Win</b><span>The result picks a winner weighted by deposit. The pot is paid out and the keeper's bond comes back.</span></li>
        </ol>
      </section>

      <section class="winners" aria-labelledby="win-h">
        <h2 id="win-h">Past winners</h2>
        <Show when={s()} fallback={<p class="mut">Loading…</p>}>
          <ul class="torn">
            <For each={[...s().logs].reverse()} fallback={<li class="mut empty">No draws yet. The first winner gets a stub here.</li>}>{(l) =>
              <li class="torn-i"><span class="torn-n">Draw #{String(l.args.draw)}</span><span class="torn-w" title={l.args.winner}>{l.args.winner.slice(0, 8)}…{l.args.winner.slice(-4)}</span><b class="torn-p">{f(l.args.prize)} BOT</b></li>}</For>
          </ul>
        </Show>
      </section>
      <footer class="foot">TicketPot on BOT Chain · <a href={EXPLORER + (cfg() ? "/address/" + cfg().address : "")} target="_blank" rel="noopener noreferrer">Contract on BOTScan</a></footer>
    </main>
  );
}
render(() => <App />, document.getElementById("root"));
