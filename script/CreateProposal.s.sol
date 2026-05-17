// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/governance/DeFiToken.sol";
import "../contracts/governance/DeFiGovernor.sol";

/// @notice Self-delegate DGT and create two demo governance proposals
contract CreateProposal is Script {
    address constant DGT = 0x3516c36c76D19Cb3fBc81B5EfFdbD11aa89BaDF4;
    address constant GOVERNOR = 0xA2F72eB781dCD791F95E4c0E4bb26DCF11a94a6C;
    address constant TIMELOCK = 0x8Ae65c04cEc1040b74ed8C425a2D79e59F5B08Dd;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // 1. Self-delegate so voting power is activated
        DeFiToken(DGT).delegate(deployer);
        console2.log("Delegated DGT to self:", deployer);

        vm.stopBroadcast();

        console2.log("\nVoting power activated.");
        console2.log("Wait 1 block, then run CreateProposalStep2.s.sol to submit proposals.");
        console2.log("(votingDelay = 7200 blocks ~30 min before Active)");
    }
}
