// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Script.sol";
import "../src/TicketPot.sol";
// forge script script/Deploy.s.sol --rpc-url <rpc> --broadcast     (env: TREASURY, ROUND_LENGTH seconds, default 7 days)
contract Deploy is Script {
    function run() external {
        address treasury = vm.envAddress("TREASURY");
        uint256 len = vm.envOr("ROUND_LENGTH", uint256(7 days));
        vm.startBroadcast();
        TicketPot p = new TicketPot(len, treasury);
        vm.stopBroadcast();
        console.log("TicketPot", address(p));
    }
}
