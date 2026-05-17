// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// ─── VULNERABLE CONTRACT ──────────────────────────────────────────────────────

/// @title VulnerableTreasury
/// @notice Intentionally vulnerable treasury with an unguarded admin function.
///         Any caller can drain the balance by calling `sweep()`.
/// @dev EDUCATIONAL DEMO — do NOT deploy to production.
contract VulnerableTreasury {
    event Swept(address indexed attacker, uint256 amount);

    receive() external payable { }

    /// @notice BUG: no access control — anyone can drain the treasury
    function sweep(address payable recipient) external {
        uint256 bal = address(this).balance;
        emit Swept(recipient, bal);
        (bool ok,) = recipient.call{ value: bal }("");
        require(ok, "transfer failed");
    }

    function balance() external view returns (uint256) {
        return address(this).balance;
    }
}

/// @notice Attacker exploiting the unguarded sweep function
contract TreasuryAttacker {
    VulnerableTreasury public immutable target;

    constructor(address target_) {
        target = VulnerableTreasury(payable(target_));
    }

    function attack() external {
        target.sweep(payable(msg.sender));
    }
}

// ─── SECURE CONTRACT ──────────────────────────────────────────────────────────

/// @title SecureTreasury
/// @notice Fixed version: `sweep` is restricted to the owner via Ownable.
///         Additional mitigation: a Timelock (see DeFiTimelock) should own this
///         so no single EOA can drain funds unilaterally.
contract SecureTreasury is Ownable {
    event Swept(address indexed recipient, uint256 amount);

    constructor(address initialOwner) Ownable(initialOwner) { }

    receive() external payable { }

    /// @notice FIX: only the owner can sweep; deploy with Timelock as owner in prod
    function sweep(address payable recipient) external onlyOwner {
        if (recipient == address(0)) revert OwnableInvalidOwner(address(0));
        uint256 bal = address(this).balance;
        emit Swept(recipient, bal);
        (bool ok,) = recipient.call{ value: bal }("");
        require(ok, "transfer failed");
    }

    function balance() external view returns (uint256) {
        return address(this).balance;
    }
}
