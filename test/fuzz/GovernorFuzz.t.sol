// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/governance/DeFiToken.sol";
import "../../contracts/governance/DeFiGovernor.sol";
import "../../contracts/governance/DeFiTimelock.sol";

/// @notice Fuzz tests for governance voting power invariants
contract GovernorFuzzTest is Test {
    DeFiToken token;
    DeFiTimelock timelock;
    DeFiGovernor governor;

    address deployer = makeAddr("deployer");

    uint256 constant INITIAL_SUPPLY = 10_000_000e18;
    uint256 constant MIN_DELAY = 2 days;

    function setUp() public {
        vm.startPrank(deployer);
        token = new DeFiToken(deployer, INITIAL_SUPPLY);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new DeFiTimelock(MIN_DELAY, proposers, executors, deployer);
        governor = new DeFiGovernor(token, timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);
        vm.stopPrank();
    }

    /// @notice Total voting power across all delegated accounts never exceeds total supply
    function testFuzz_votingPowerNeverExceedsTotalSupply(address a, address b, uint128 amtA, uint128 amtB) public {
        vm.assume(a != address(0) && b != address(0) && a != b && a != deployer && b != deployer);
        uint256 supply = token.totalSupply();
        uint256 toA = bound(amtA, 0, supply / 2);
        uint256 toB = bound(amtB, 0, supply - toA);

        vm.startPrank(deployer);
        if (toA > 0) token.transfer(a, toA);
        if (toB > 0) token.transfer(b, toB);
        vm.stopPrank();

        vm.prank(a);
        token.delegate(a);
        vm.prank(b);
        token.delegate(b);
        vm.prank(deployer);
        token.delegate(deployer);

        vm.roll(block.number + 1);
        uint256 blockNum = block.number - 1;

        uint256 votesA = token.getPastVotes(a, blockNum);
        uint256 votesB = token.getPastVotes(b, blockNum);
        uint256 votesDeployer = token.getPastVotes(deployer, blockNum);

        assertLe(votesA + votesB + votesDeployer, supply);
    }

    /// @notice Delegating to self gives exactly the delegator's balance as voting power
    function testFuzz_selfDelegateMatchesBalance(uint128 amount) public {
        uint256 amt = bound(amount, 1, INITIAL_SUPPLY);
        address user = makeAddr("user");
        vm.prank(deployer);
        token.transfer(user, amt);
        vm.prank(user);
        token.delegate(user);
        vm.roll(block.number + 1);
        assertEq(token.getPastVotes(user, block.number - 1), amt);
    }

    /// @notice Transferring tokens after delegation reduces sender's voting power
    function testFuzz_transferReducesSenderVotingPower(uint128 amount, uint128 transfer_) public {
        uint256 amt = bound(amount, 1e18, INITIAL_SUPPLY);
        uint256 trf = bound(transfer_, 1, amt);
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");

        vm.prank(deployer);
        token.transfer(sender, amt);
        vm.prank(sender);
        token.delegate(sender);
        vm.roll(block.number + 1);

        uint256 votesBefore = token.getPastVotes(sender, block.number - 1);
        assertEq(votesBefore, amt);

        vm.prank(sender);
        token.transfer(receiver, trf);
        vm.roll(block.number + 1);

        uint256 votesAfter = token.getPastVotes(sender, block.number - 1);
        assertEq(votesAfter, amt - trf);
    }

    /// @notice Quorum at any block ≤ total supply
    function testFuzz_quorumNeverExceedsSupply(uint256 blockOffset) public {
        uint256 blk = bound(blockOffset, 0, 1000);
        vm.roll(block.number + blk + 1);
        // snapshot block must be in the past
        uint256 snapshotBlock = block.number - 1;
        uint256 q = governor.quorum(snapshotBlock);
        assertLe(q, token.totalSupply());
    }
}
