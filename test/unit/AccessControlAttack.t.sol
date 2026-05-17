// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/attacks/AccessControlAttack.sol";

/// @notice Case study: unguarded admin function (before) vs Ownable-protected (after)
contract AccessControlAttackTest is Test {
    VulnerableTreasury vulnerable;
    TreasuryAttacker attacker;
    SecureTreasury secure;

    address owner = makeAddr("owner");
    address adversary = makeAddr("adversary");

    uint256 constant TREASURY_BALANCE = 10 ether;

    function setUp() public {
        vulnerable = new VulnerableTreasury();
        attacker = new TreasuryAttacker(address(vulnerable));

        vm.prank(owner);
        secure = new SecureTreasury(owner);

        // Fund both treasuries
        vm.deal(address(vulnerable), TREASURY_BALANCE);
        vm.deal(address(secure), TREASURY_BALANCE);
    }

    // ─── BEFORE: attack succeeds on vulnerable contract ──────────────────────

    function test_vulnerableTreasury_drainedByAnyone() public {
        uint256 adversaryBalBefore = adversary.balance;

        vm.prank(adversary);
        attacker.attack();

        assertEq(address(vulnerable).balance, 0, "treasury should be empty");
        assertEq(adversary.balance, adversaryBalBefore + TREASURY_BALANCE, "adversary received funds");
    }

    function test_vulnerableTreasury_anyoneCanCallSweepDirectly() public {
        address random = makeAddr("random");
        vm.deal(random, 0);

        vm.prank(random);
        vulnerable.sweep(payable(random));

        assertEq(address(vulnerable).balance, 0);
        assertEq(random.balance, TREASURY_BALANCE);
    }

    // ─── AFTER: attack fails on secure contract ───────────────────────────────

    function test_secureTreasury_onlyOwnerCanSweep() public {
        vm.prank(adversary);
        vm.expectRevert();
        secure.sweep(payable(adversary));

        // Treasury untouched
        assertEq(address(secure).balance, TREASURY_BALANCE);
    }

    function test_secureTreasury_ownerCanSweep() public {
        address recipient = makeAddr("recipient");
        vm.prank(owner);
        secure.sweep(payable(recipient));

        assertEq(address(secure).balance, 0);
        assertEq(recipient.balance, TREASURY_BALANCE);
    }

    function test_secureTreasury_cannotSweepToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        secure.sweep(payable(address(0)));
    }
}
