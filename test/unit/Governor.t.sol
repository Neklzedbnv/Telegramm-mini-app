// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/governance/DeFiToken.sol";
import "../../contracts/governance/DeFiGovernor.sol";
import "../../contracts/governance/DeFiTimelock.sol";
import "@openzeppelin/contracts/governance/IGovernor.sol";

/// @notice End-to-end test of the governance lifecycle: propose → vote → queue → execute
contract GovernorTest is Test {
    DeFiToken token;
    DeFiTimelock timelock;
    DeFiGovernor governor;

    address deployer = makeAddr("deployer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant INITIAL_SUPPLY = 10_000_000e18; // 10M tokens
    uint256 constant MIN_DELAY = 2 days;

    function setUp() public {
        vm.startPrank(deployer);

        token = new DeFiToken(deployer, INITIAL_SUPPLY);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // anyone can execute
        timelock = new DeFiTimelock(MIN_DELAY, proposers, executors, deployer);

        governor = new DeFiGovernor(token, timelock);

        // Grant proposer + canceller roles to governor
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        // Renounce admin so timelock is self-governing
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        // Distribute tokens and delegate before taking snapshot
        token.transfer(alice, 5_000_000e18);
        token.transfer(bob, 4_000_000e18);
        vm.stopPrank();

        vm.prank(deployer);
        token.delegateToSelf();
        vm.prank(alice);
        token.delegateToSelf();
        vm.prank(bob);
        token.delegateToSelf();
    }

    // ─── Parameter checks ─────────────────────────────────────────────────────

    function test_votingDelay() public view {
        assertEq(governor.votingDelay(), 7200);
    }

    function test_votingPeriod() public view {
        assertEq(governor.votingPeriod(), 50_400);
    }

    function test_quorumNumerator() public view {
        assertEq(governor.quorumNumerator(), 4);
    }

    function test_proposalThreshold() public view {
        assertEq(governor.proposalThreshold(), 1_000_000e18);
    }

    function test_timelockMinDelay() public view {
        assertEq(timelock.getMinDelay(), MIN_DELAY);
    }

    // ─── Full lifecycle ───────────────────────────────────────────────────────

    function test_fullGovernanceLifecycle() public {
        // Prepare a dummy proposal: call timelock's own updateDelay (no-op to demonstrate lifecycle)
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(timelock);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(TimelockController.updateDelay.selector, MIN_DELAY);
        string memory description = "Proposal #1: keep timelock delay";
        bytes32 descHash = keccak256(bytes(description));

        // Alice proposes (has 5M > threshold of 1M)
        vm.roll(block.number + 1);
        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // State: Pending during voting delay
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));

        // Roll past voting delay
        vm.roll(block.number + governor.votingDelay() + 1);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Active));

        // Alice and Bob vote For
        vm.prank(alice);
        governor.castVote(proposalId, 1); // 1 = For
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        // Roll past voting period
        vm.roll(block.number + governor.votingPeriod() + 1);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));

        // Queue in timelock
        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));

        // Wait timelock delay
        vm.warp(block.timestamp + MIN_DELAY + 1);

        // Execute
        governor.execute(targets, values, calldatas, descHash);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
    }

    function test_proposalDefeated_insufficientVotes() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(timelock);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(TimelockController.updateDelay.selector, MIN_DELAY);
        string memory description = "Proposal #2: defeated";

        vm.roll(block.number + 1);
        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);

        // Only deployer votes Against (1M tokens — below quorum of 4% of 10M = 400k, but Against)
        vm.prank(deployer);
        governor.castVote(proposalId, 0); // 0 = Against

        vm.roll(block.number + governor.votingPeriod() + 1);
        // No votes For, so defeated
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_cannotProposeBelow_threshold() public {
        address newUser = makeAddr("poor");
        vm.prank(deployer);
        token.transfer(newUser, 500_000e18); // less than 1M threshold
        vm.prank(newUser);
        token.delegateToSelf();
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(timelock);

        vm.prank(newUser);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "below threshold");
    }

    function test_cannotVoteTwice() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(timelock);
        string memory description = "Proposal #3: double vote";

        vm.roll(block.number + 1);
        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(alice);
        vm.expectRevert();
        governor.castVote(proposalId, 1);
    }
}
