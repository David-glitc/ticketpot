// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../src/TicketPot.sol";
// forge test --match-contract Fork --fork-url https://rpc.botchain.ai   (read-only; skipped without a fork)
contract Fork is Test {
    function test_drawOnBotChainFork() public {
        if (block.chainid != 677) { vm.skip(true); }
        TicketPot p = new TicketPot(7 days, address(0xFEE));
        address a = address(0xA1); address b = address(0xB2); address k = address(0x4E);
        vm.deal(a, 100 ether); vm.deal(b, 100 ether); vm.deal(k, 10 ether);
        vm.prank(a); p.deposit{value: 10 ether}(); vm.prank(b); p.deposit{value: 30 ether}();
        vm.deal(address(this), 10 ether); p.sponsor{value: 10 ether}();
        vm.warp(block.timestamp + 8 days);
        address[] memory w = new address[](2); w[0] = a; w[1] = b; p.sync(w);
        bytes32 s = keccak256("fork");
        uint256 bond = p.bondRequired();
        uint256 start = block.number;
        vm.prank(k); p.commitDraw{value: bond}(keccak256(abi.encode(s, k)));
        vm.roll(start + 11);
        // the real chain keeps hashes for recent blocks; on a fork blockhash of a rolled block is zero, so the contract's seed
        // still depends on the secret. Confirm the draw completes and pays exactly the pot.
        vm.prank(k); p.revealDraw(s);
        assertEq(p.owed(a) + p.owed(b) + p.owed(k), 9.5 ether);
        emit log_named_uint("chain", block.chainid); emit log_named_uint("fork block", start);
    }
    receive() external payable {}
}
