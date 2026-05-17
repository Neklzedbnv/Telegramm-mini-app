// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/attacks/ReentrancyAttack.sol";

/// @notice Case study: reentrancy bug (before) vs CEI + ReentrancyGuard (after)
contract ReentrancyAttackTest is Test {
    VulnerableETHBank vulnerable;
    SecureETHBank secure;
    ReentrancyAttacker attacker;

    address victim = makeAddr("victim");
    address adversary = makeAddr("adversary");

    uint256 constant VICTIM_DEPOSIT = 9 ether;
    uint256 constant ATTACK_DEPOSIT = 1 ether;

    function setUp() public {
        vulnerable = new VulnerableETHBank();
        secure = new SecureETHBank();

        // Victim deposits into the vulnerable bank
        vm.deal(victim, VICTIM_DEPOSIT);
        vm.prank(victim);
        vulnerable.deposit{ value: VICTIM_DEPOSIT }();

        // Attacker contract targets the vulnerable bank
        attacker = new ReentrancyAttacker(payable(address(vulnerable)));
    }

    // ─── BEFORE: attack succeeds on vulnerable contract ──────────────────────

    function test_reentrancy_attackSucceedsOnVulnerable() public {
        vm.deal(adversary, ATTACK_DEPOSIT);
        uint256 bankBalanceBefore = address(vulnerable).balance;

        vm.prank(adversary);
        attacker.attack{ value: ATTACK_DEPOSIT }();

        // Attacker drained more than their initial deposit
        assertGt(adversary.balance, ATTACK_DEPOSIT, "attacker should profit from reentrancy");
        assertLt(address(vulnerable).balance, bankBalanceBefore, "bank should be drained");
    }

    function test_reentrancy_victimFundsStolen() public {
        vm.deal(adversary, ATTACK_DEPOSIT);

        uint256 victimBalanceBefore = vulnerable.balances(victim);
        assertEq(victimBalanceBefore, VICTIM_DEPOSIT);

        vm.prank(adversary);
        attacker.attack{ value: ATTACK_DEPOSIT }();

        // Bank is empty — victim can no longer withdraw their funds
        assertEq(address(vulnerable).balance, 0, "bank should be drained empty");
    }

    // ─── AFTER: attack fails on secure contract ───────────────────────────────

    function test_reentrancy_attackFailsOnSecure() public {
        // Fund the secure bank with victim deposits
        vm.deal(victim, VICTIM_DEPOSIT);
        vm.prank(victim);
        secure.deposit{ value: VICTIM_DEPOSIT }();

        // Deploy a new attacker targeting the secure bank
        ReentrancyAttacker secureAttacker = new ReentrancyAttacker(payable(address(secure)));

        vm.deal(adversary, ATTACK_DEPOSIT);
        vm.prank(adversary);
        // ReentrancyGuard reverts on re-entry
        vm.expectRevert();
        secureAttacker.attack{ value: ATTACK_DEPOSIT }();

        // Secure bank is intact
        assertEq(address(secure).balance, VICTIM_DEPOSIT, "secure bank should be untouched");
    }

    function test_reentrancy_normalWithdrawWorksOnSecure() public {
        vm.deal(victim, VICTIM_DEPOSIT);
        vm.prank(victim);
        secure.deposit{ value: VICTIM_DEPOSIT }();

        uint256 balanceBefore = victim.balance;

        vm.prank(victim);
        secure.withdraw();

        assertEq(victim.balance, balanceBefore + VICTIM_DEPOSIT, "victim should receive funds back");
        assertEq(secure.balances(victim), 0, "balance should be zeroed");
    }

    function test_reentrancy_cannotWithdrawTwice() public {
        vm.deal(victim, VICTIM_DEPOSIT);
        vm.prank(victim);
        secure.deposit{ value: VICTIM_DEPOSIT }();

        vm.prank(victim);
        secure.withdraw();

        // Second withdraw should revert with NothingToWithdraw
        vm.prank(victim);
        vm.expectRevert(SecureETHBank.NothingToWithdraw.selector);
        secure.withdraw();
    }
}
