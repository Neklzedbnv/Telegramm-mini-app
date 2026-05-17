// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/governance/DeFiGovernor.sol";
import "../contracts/governance/DeFiTimelock.sol";
import "../contracts/core/LendingPoolV1.sol";
import "../contracts/governance/DeFiToken.sol";

/// @notice Post-deployment sanity checks.
///         Run with:
///   TIMELOCK=<> GOVERNOR=<> LENDING_POOL=<> DEFI_TOKEN=<> \
///   forge script script/PostDeploy.s.sol --rpc-url $RPC_URL
contract PostDeploy is Script {
    DeFiTimelock timelock;
    DeFiGovernor gov;
    LendingPoolV1 pool;
    DeFiToken token;

    function run() external {
        timelock = DeFiTimelock(payable(vm.envAddress("TIMELOCK")));
        gov = DeFiGovernor(payable(vm.envAddress("GOVERNOR")));
        pool = LendingPoolV1(vm.envAddress("LENDING_POOL"));
        token = DeFiToken(vm.envAddress("DEFI_TOKEN"));

        console2.log("=== POST-DEPLOY VERIFICATION ===");
        _checkTimelock();
        _checkGovernor();
        _checkOwnership();
        console2.log("\n=== ALL CHECKS PASSED ===");
    }

    function _checkTimelock() internal view {
        uint256 delay = timelock.getMinDelay();
        console2.log("Timelock min delay (s):   ", delay);
        require(delay == 2 days, "FAIL: Timelock delay != 2 days");
        console2.log("  [PASS] min delay == 2 days");

        bool isProposer = timelock.hasRole(timelock.PROPOSER_ROLE(), address(gov));
        console2.log("Governor is proposer:     ", isProposer);
        require(isProposer, "FAIL: Governor missing PROPOSER_ROLE");
        console2.log("  [PASS] Governor has PROPOSER_ROLE");

        bool deployerIsAdmin = timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), msg.sender);
        console2.log("Deployer has admin:       ", deployerIsAdmin);
        require(!deployerIsAdmin, "FAIL: Deployer retains Timelock admin");
        console2.log("  [PASS] No deployer admin remaining");
    }

    function _checkGovernor() internal view {
        console2.log("votingDelay:              ", gov.votingDelay());
        require(gov.votingDelay() == 7200, "FAIL: votingDelay != 7200");
        console2.log("  [PASS] votingDelay == 7200 blocks");

        console2.log("votingPeriod:             ", gov.votingPeriod());
        require(gov.votingPeriod() == 50_400, "FAIL: votingPeriod != 50400");
        console2.log("  [PASS] votingPeriod == 50400 blocks");

        console2.log("quorumNumerator:          ", gov.quorumNumerator());
        require(gov.quorumNumerator() == 4, "FAIL: quorumNumerator != 4");
        console2.log("  [PASS] quorum == 4%%");

        console2.log("proposalThreshold:        ", gov.proposalThreshold());
        require(gov.proposalThreshold() == 1_000_000e18, "FAIL: proposalThreshold wrong");
        console2.log("  [PASS] proposalThreshold == 1_000_000e18");
    }

    function _checkOwnership() internal view {
        address poolOwner = pool.owner();
        console2.log("LendingPool owner:        ", poolOwner);
        require(poolOwner == address(timelock), "FAIL: LendingPool owner != Timelock");
        console2.log("  [PASS] LendingPool owned by Timelock");

        address tokenOwner = token.owner();
        console2.log("DeFiToken owner:          ", tokenOwner);
        require(tokenOwner == address(timelock), "FAIL: DeFiToken owner != Timelock");
        console2.log("  [PASS] DeFiToken owned by Timelock");
    }
}
