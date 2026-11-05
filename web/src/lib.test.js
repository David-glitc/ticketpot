import { describe, it, expect } from "vitest";
import { countdown, winChance, winnerPrize, sponsorNet, drawStep } from "./lib.js";
describe("lib", () => {
  it("countdown", () => { expect(countdown(0)).toBe("now"); expect(countdown(90061)).toBe("1d 1h"); expect(countdown(125)).toBe("2m 5s"); });
  it("odds and prizes", () => {
    expect(winChance(10n, 40n)).toBe(0.25); expect(winChance(1n, 0n)).toBe(0);
    expect(winnerPrize(100n)).toBe(99n); expect(sponsorNet(100n)).toBe(95n);
  });
  it("draw steps", () => {
    const base = { now: 100, nextDraw: 50, locked: false, commitBlock: 0, block: 0, pot: 1n, treeTotal: 1n, pendingCut: 0n };
    expect(drawStep({ ...base, now: 10 }).key).toBe("early");
    expect(drawStep(base).key).toBe("commit");
    expect(drawStep({ ...base, pendingCut: 1n }).key).toBe("cuts");
    expect(drawStep({ ...base, pot: 0n }).key).toBe("empty");
    expect(drawStep({ ...base, locked: true, commitBlock: 100, block: 105 }).key).toBe("wait");
    expect(drawStep({ ...base, locked: true, commitBlock: 100, block: 111 }).key).toBe("reveal");
    expect(drawStep({ ...base, locked: true, commitBlock: 100, block: 301 }).key).toBe("slash");
  });
});
