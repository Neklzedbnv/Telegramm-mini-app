// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title DeFiToken
/// @notice ERC20 governance token with on-chain voting via ERC20Votes and gasless approvals via ERC20Permit
/// @dev Voting power tracks balance changes via OpenZeppelin's checkpoint system.
///      Delegates must be set before checkpoints are created; undelegated tokens carry zero voting weight.
///      Mint is restricted to the owner (e.g., governance timelock or multisig).
contract DeFiToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    // ─── Constants ────────────────────────────────────────────────────────────

    /// @notice Maximum total supply cap (100 million tokens, 18 decimals)
    uint256 public constant MAX_SUPPLY = 100_000_000e18;

    // ─── Events ───────────────────────────────────────────────────────────────

    event Minted(address indexed to, uint256 amount);

    // ─── Errors ───────────────────────────────────────────────────────────────

    /// @notice Thrown when a mint would exceed MAX_SUPPLY
    error ExceedsMaxSupply(uint256 current, uint256 requested, uint256 max);

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @param initialOwner  Address that receives owner rights and initial supply
    /// @param initialSupply Amount minted to initialOwner at construction (no permit required)
    constructor(address initialOwner, uint256 initialSupply)
        ERC20("DeFi Governance Token", "DGT")
        ERC20Permit("DeFi Governance Token")
        Ownable(initialOwner)
    {
        if (initialSupply > MAX_SUPPLY) {
            revert ExceedsMaxSupply(0, initialSupply, MAX_SUPPLY);
        }
        _mint(initialOwner, initialSupply);
    }

    // ─── Owner Functions ──────────────────────────────────────────────────────

    /// @notice Mint new tokens (only owner; respects MAX_SUPPLY cap)
    /// @param to     Recipient of the minted tokens
    /// @param amount Number of tokens to mint (in wei, 18 decimals)
    function mint(address to, uint256 amount) external onlyOwner {
        uint256 current = totalSupply();
        if (current + amount > MAX_SUPPLY) {
            revert ExceedsMaxSupply(current, amount, MAX_SUPPLY);
        }
        _mint(to, amount);
        emit Minted(to, amount);
    }

    // ─── Governance Helpers ───────────────────────────────────────────────────

    /// @notice Delegate voting power to self in a single transaction
    /// @dev Useful for new token holders who want immediate voting power
    function delegateToSelf() external {
        delegate(msg.sender);
    }

    // ─── Required Overrides ───────────────────────────────────────────────────

    /// @dev Resolves the diamond inheritance between ERC20 and ERC20Votes.
    ///      ERC20Votes hooks into every balance change via _update to update voting checkpoints.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /// @dev Resolves the nonce management between ERC20Permit and Nonces.
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
