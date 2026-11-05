// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../src/TicketPot.sol";

contract Handler is Test {
    TicketPot public p; address[3] public actors = [address(0xA1), address(0xB2), address(0xC3)];
    uint256 public deposited; uint256 public withdrawn; uint256 n;
    constructor(TicketPot _p) { p = _p; for (uint256 i; i < 3; i++) vm.deal(actors[i], 1e24); vm.deal(address(this), 1e24); }
    function deposit(uint256 who, uint256 amt) external { who %= 3; amt = bound(amt, 0.01 ether, 50 ether); vm.prank(actors[who]); p.deposit{value: amt}(); deposited += amt; }
    function withdraw(uint256 who, uint256 amt) external { who %= 3; uint256 b = p.balanceOf(actors[who]); if (b == 0) return; amt = bound(amt, 1, b); vm.prank(actors[who]); p.withdraw(amt); withdrawn += amt; }
    function sponsor(uint256 amt) external { amt = bound(amt, 0.01 ether, 50 ether); p.sponsor{value: amt}(); }
    function sync() external { address[] memory w = new address[](3); for (uint256 i; i < 3; i++) w[i] = actors[i]; p.sync(w); }
    function warp(uint256 t) external { vm.warp(block.timestamp + bound(t, 1, 3 days)); vm.roll(block.number + 1); }
    function draw(uint256 seed) external {
        if (p.locked()) { vm.roll(block.number + 11); try p.revealDraw(bytes32(seed)) {} catch {} try p.slashCommit() {} catch {} return; }
        uint256 bond = p.bondRequired(); n++;
        try p.commitDraw{value: bond}(keccak256(abi.encode(bytes32(seed), address(this)))) {} catch {}
    }
    receive() external payable {}
}

contract InvariantTest is Test {
    TicketPot p; Handler h;
    function setUp() public { p = new TicketPot(7 days, address(0xFEE)); h = new Handler(p); targetContract(address(h)); }
    function invariant_solvent() public view { assertGe(address(p).balance, p.totalPrincipal() + p.pot() + p.totalOwed() + p.bondsHeld()); }
    function invariant_principalAccounting() public view { assertEq(p.totalPrincipal(), h.deposited() - h.withdrawn()); }
    function invariant_treeCoversEligible() public view { assertLe(p.treeTotal(), p.totalPrincipal() + p.totalPendingCut()); }
}
