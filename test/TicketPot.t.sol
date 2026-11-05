// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../src/TicketPot.sol";

contract TicketPotTest is Test {
    TicketPot pot;
    address treasury = address(0xFEE);
    address alice = address(0xA1); address bob = address(0xB2); address carol = address(0xC3);
    address keeper = address(0x4E);
    address sponsorAddr = address(0x5B);
    uint256 constant WEEK = 7 days;

    function setUp() public {
        pot = new TicketPot(WEEK, treasury);
        vm.deal(alice, 1000 ether); vm.deal(bob, 1000 ether); vm.deal(carol, 1000 ether);
        vm.deal(keeper, 100 ether); vm.deal(sponsorAddr, 1000 ether);
    }

    function _syncAll() internal { address[] memory w = new address[](3); w[0]=alice; w[1]=bob; w[2]=carol; pot.sync(w); }
    function _toDrawTime() internal { vm.warp(block.timestamp + WEEK + pot.drawGrace() + 1); }
    function _invariant() internal view {
        assertGe(address(pot).balance, pot.totalPrincipal() + pot.pot() + pot.totalOwed() + pot.bondsHeld(), "solvent");
    }
    function _commit(bytes32 secret) internal { uint256 bond = pot.bondRequired(); vm.prank(keeper); pot.commitDraw{value: bond}(keccak256(abi.encode(secret, keeper))); }
    function _draw(bytes32 secret) internal {
        uint256 bond = pot.bondRequired();
        vm.prank(keeper); pot.commitDraw{value: bond}(keccak256(abi.encode(secret, keeper)));
        vm.roll(block.number + 11);
        vm.prank(keeper); pot.revealDraw(secret);
    }

    function test_depositWithdrawPrincipal() public {
        vm.prank(alice); pot.deposit{value: 10 ether}();
        assertEq(pot.balanceOf(alice), 10 ether);
        vm.prank(alice); pot.withdraw(4 ether);
        vm.prank(alice); pot.withdraw(6 ether);
        assertEq(alice.balance, 1000 ether);
        assertEq(pot.totalPrincipal(), 0);
        _invariant();
    }
    function test_minDeposit() public { vm.prank(alice); vm.expectRevert(TicketPot.BadParam.selector); pot.deposit{value: 1}(); }
    function test_overWithdrawReverts() public {
        vm.prank(alice); pot.deposit{value: 1 ether}();
        vm.prank(alice); vm.expectRevert(TicketPot.BadParam.selector); pot.withdraw(2 ether);
    }
    function test_sponsorFeeAndPot() public {
        vm.prank(sponsorAddr); pot.sponsor{value: 100 ether}();
        assertEq(pot.pot(), 95 ether); assertEq(pot.owed(treasury), 5 ether);
        (bool ok,) = address(pot).call{value: 1 ether}(""); assertTrue(ok); assertEq(pot.pot(), 96 ether);
    }
    function test_drawTimingAndPreconditions() public {
        vm.prank(alice); pot.deposit{value: 10 ether}();
        vm.prank(sponsorAddr); pot.sponsor{value: 10 ether}();
        vm.prank(keeper); vm.expectRevert(TicketPot.TooEarly.selector); pot.commitDraw{value: 1 ether}(bytes32(0));
        vm.warp(block.timestamp + WEEK - 10); // still round 1
        vm.prank(keeper); vm.expectRevert(TicketPot.TooEarly.selector); pot.commitDraw{value: 1 ether}(bytes32(0));
        vm.warp(block.timestamp + 11); // round 2 but inside grace
        vm.prank(keeper); vm.expectRevert(TicketPot.TooEarly.selector); pot.commitDraw{value: 1 ether}(bytes32(0));
    }
    function test_freshDepositsNotEligibleUntilNextRound() public {
        vm.prank(alice); pot.deposit{value: 10 ether}();
        vm.prank(sponsorAddr); pot.sponsor{value: 10 ether}();
        _toDrawTime();
        // alice never synced: draw has no weight
        vm.prank(keeper); vm.expectRevert(TicketPot.WrongState.selector); pot.commitDraw{value: 1 ether}(bytes32(0));
        _syncAll();
        assertEq(pot.weightOf(alice), 10 ether);
        // bob deposits now (round 2): not eligible until round 3
        vm.prank(bob); pot.deposit{value: 1000 ether}();
        _syncAll();
        assertEq(pot.weightOf(bob), 0);
        _draw(bytes32(uint256(1)));
        assertEq(pot.owed(alice), 9.5 ether * 99 / 100); // sole eligible depositor wins
        assertEq(pot.owed(bob), 0);
    }
    function test_fullDrawFlow() public {
        vm.prank(alice); pot.deposit{value: 30 ether}();
        vm.prank(bob); pot.deposit{value: 10 ether}();
        vm.prank(sponsorAddr); pot.sponsor{value: 100 ether}();
        _toDrawTime(); _syncAll();
        uint256 keeperBefore = keeper.balance;
        _draw(bytes32(uint256(42)));
        assertEq(pot.pot(), 0);
        assertEq(pot.drawCount(), 1);
        uint256 w = pot.owed(alice) + pot.owed(bob);
        assertEq(w, 95 ether * 99 / 100);
        assertEq(pot.owed(keeper), 0.95 ether);
        assertEq(keeper.balance, keeperBefore); // bond returned; reward is pull
        vm.prank(keeper); pot.claim();
        assertEq(keeper.balance, keeperBefore + 0.95 ether);
        // second draw in same round impossible
        vm.prank(sponsorAddr); pot.sponsor{value: 10 ether}();
        vm.prank(keeper); vm.expectRevert(TicketPot.TooEarly.selector); pot.commitDraw{value: 1 ether}(bytes32(0));
        _invariant();
    }
    function test_wrongSecretAndTiming() public {
        vm.prank(alice); pot.deposit{value: 10 ether}(); vm.prank(sponsorAddr); pot.sponsor{value: 10 ether}();
        _toDrawTime(); _syncAll();
        bytes32 s = bytes32(uint256(7)); uint256 bond = pot.bondRequired();
        vm.prank(keeper); pot.commitDraw{value: bond}(keccak256(abi.encode(s, keeper)));
        vm.prank(keeper); vm.expectRevert(TicketPot.TooEarly.selector); pot.revealDraw(s);
        vm.roll(block.number + 11);
        vm.prank(keeper); vm.expectRevert(TicketPot.BadParam.selector); pot.revealDraw(bytes32(uint256(8)));
        vm.prank(bob); vm.expectRevert(TicketPot.WrongState.selector); pot.revealDraw(s); // not the committer
        vm.roll(block.number + 200);
        vm.prank(keeper); vm.expectRevert(TicketPot.TooLate.selector); pot.revealDraw(s);
    }
    function test_slashAfterMissedReveal_thenRecommit() public {
        vm.prank(alice); pot.deposit{value: 10 ether}(); vm.prank(sponsorAddr); pot.sponsor{value: 20 ether}();
        _toDrawTime(); _syncAll();
        uint256 bond = pot.bondRequired(); uint256 potBefore = pot.pot();
        vm.prank(keeper); pot.commitDraw{value: bond}(keccak256("x"));
        vm.expectRevert(TicketPot.TooEarly.selector); pot.slashCommit();
        vm.roll(block.number + 201);
        pot.slashCommit();
        assertEq(pot.pot(), potBefore + bond);
        assertFalse(pot.locked());
        _draw(bytes32(uint256(5)));
        assertEq(pot.owed(alice), (potBefore + bond) * 99 / 100);
    }
    function test_withdrawDuringLockKeepsDrawFrozenAndIsAppliedAfter() public {
        vm.prank(alice); pot.deposit{value: 10 ether}(); vm.prank(bob); pot.deposit{value: 10 ether}();
        vm.prank(sponsorAddr); pot.sponsor{value: 20 ether}();
        _toDrawTime(); _syncAll();
        _commit(bytes32(uint256(9)));
        vm.prank(alice); pot.withdraw(10 ether); // allowed
        assertEq(alice.balance, 1000 ether);
        assertEq(pot.treeTotal(), 20 ether); // tree frozen
        assertEq(pot.totalPendingCut(), 10 ether);
        vm.prank(bob); pot.deposit{value: 1 ether}();
        vm.roll(block.number + 11);
        vm.prank(keeper); pot.revealDraw(bytes32(uint256(9)));
        // next commit blocked until cut applied
        vm.warp(block.timestamp + WEEK);
        vm.prank(sponsorAddr); pot.sponsor{value: 10 ether}();
        vm.prank(keeper); vm.expectRevert(TicketPot.WrongState.selector); pot.commitDraw{value: 1 ether}(bytes32(0));
        _syncAll();
        assertEq(pot.totalPendingCut(), 0);
        assertEq(pot.treeTotal(), 11 ether); // bob 10 + bob's 1 fresh now eligible
        _invariant();
    }
    function test_prizeWinnerKeepsPrizeAfterExit() public {
        vm.prank(alice); pot.deposit{value: 10 ether}(); vm.prank(sponsorAddr); pot.sponsor{value: 10 ether}();
        _toDrawTime(); _syncAll();
        _commit(bytes32(uint256(3)));
        vm.prank(alice); pot.withdraw(10 ether);
        vm.roll(block.number + 11); vm.prank(keeper); pot.revealDraw(bytes32(uint256(3)));
        assertEq(pot.owed(alice), 9.5 ether * 99 / 100);
        vm.prank(alice); pot.claim();
        assertGt(alice.balance, 1000 ether);
    }
    function test_distributionIsProportional() public {
        // weights 1:3 -> across many seeds bob should win ~75%
        vm.prank(alice); pot.deposit{value: 10 ether}(); vm.prank(bob); pot.deposit{value: 30 ether}();
        _toDrawTime(); _syncAll();
        uint256 bobWins; uint256 N = 200;
        for (uint256 i; i < N; i++) {
            uint256 snap = vm.snapshotState();
            vm.prank(sponsorAddr); pot.sponsor{value: 10 ether}();
            _commit(bytes32(i));
            vm.roll(block.number + 11 + i % 7); // vary blockhash
            vm.prank(keeper); pot.revealDraw(bytes32(i));
            if (pot.owed(bob) > 0) bobWins++;
            vm.revertToState(snap);
            vm.roll(block.number + 1);
        }
        assertGt(bobWins, 130); assertLt(bobWins, 170);
    }
    function test_selfClaimAndReentrancyGuard() public {
        Attacker a = new Attacker(pot); vm.deal(address(a), 10 ether);
        vm.prank(alice); pot.deposit{value: 5 ether}();
        a.dep{value: 5 ether}();
        vm.expectRevert(TicketPot.Failed.selector); a.attackWithdraw();
        assertEq(pot.balanceOf(address(a)), 5 ether);
    }
    function test_treasuryCannotTouchPrincipal() public {
        vm.prank(alice); pot.deposit{value: 10 ether}();
        vm.prank(treasury); vm.expectRevert(TicketPot.Nothing.selector); pot.claim();
    }

    // ---- fuzz: principal is always fully withdrawable, whatever happens in between
    function testFuzz_principalAlwaysReturned(uint96 a1, uint96 b1, uint96 sp, uint8 order) public {
        uint256 A = bound(a1, 0.01 ether, 100 ether); uint256 B = bound(b1, 0.01 ether, 100 ether); uint256 S = bound(sp, 0.01 ether, 100 ether);
        vm.prank(alice); pot.deposit{value: A}(); vm.prank(bob); pot.deposit{value: B}();
        vm.prank(sponsorAddr); pot.sponsor{value: S}();
        _toDrawTime(); _syncAll();
        _commit(bytes32(uint256(order)));
        if (order % 2 == 0) { vm.prank(alice); pot.withdraw(A); }
        vm.roll(block.number + 11);
        vm.prank(keeper); pot.revealDraw(bytes32(uint256(order)));
        if (order % 2 == 1) { vm.prank(alice); pot.withdraw(A); }
        vm.prank(bob); pot.withdraw(B);
        assertEq(alice.balance, 1000 ether, "alice principal intact");
        assertEq(bob.balance, 1000 ether);
        assertEq(pot.totalPrincipal(), 0);
        _invariant();
    }
}

contract Attacker {
    TicketPot p; constructor(TicketPot _p) { p = _p; }
    function dep() external payable { p.deposit{value: msg.value}(); }
    function attackWithdraw() external { p.withdraw(5 ether); }
    receive() external payable { if (address(p).balance > 0) p.withdraw(1 ether); }
}
