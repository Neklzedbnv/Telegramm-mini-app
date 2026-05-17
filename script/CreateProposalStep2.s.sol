// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/governance/DeFiGovernor.sol";

/// @notice Submit two demo governance proposals after self-delegation
contract CreateProposalStep2 is Script {
    address constant GOVERNOR  = 0xA2F72eB781dCD791F95E4c0E4bb26DCF11a94a6C;
    address constant TIMELOCK  = 0x8Ae65c04cEc1040b74ed8C425a2D79e59F5B08Dd;
    address constant POOL      = 0xC047D3248eE6F4D5ba570d8cD8D904C2D3a0A9F9;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        DeFiGovernor gov = DeFiGovernor(payable(GOVERNOR));

        // Proposal 1: raise LTV to 80%
        address[] memory targets1 = new address[](1);
        uint256[] memory values1  = new uint256[](1);
        bytes[]   memory calldatas1 = new bytes[](1);
        targets1[0]   = POOL;
        values1[0]    = 0;
        calldatas1[0] = abi.encodeWithSignature("setLTV(uint256)", 8000);

        uint256 pid1 = gov.propose(
            targets1, values1, calldatas1,
            "PIP-01: Increase LTV cap for ETH collateral to 80%"
        );
        console2.log("Proposal 1 ID:", pid1);

        // Proposal 2: update oracle staleness threshold
        address[] memory targets2 = new address[](1);
        uint256[] memory values2  = new uint256[](1);
        bytes[]   memory calldatas2 = new bytes[](1);
        targets2[0]   = POOL;
        values2[0]    = 0;
        calldatas2[0] = abi.encodeWithSignature("setStalenessThreshold(uint256)", 7200);

        uint256 pid2 = gov.propose(
            targets2, values2, calldatas2,
            "PIP-02: Integrate Chainlink oracle for Arbitrum Sepolia"
        );
        console2.log("Proposal 2 ID:", pid2);

        vm.stopBroadcast();

        console2.log("\nCopy these IDs into frontend/src/config/contracts.ts PROPOSAL_IDS");
    }
}
