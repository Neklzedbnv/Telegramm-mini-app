// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title PositionNFT
/// @notice ERC-721 "loan receipt" minted once per user when they first deposit into the lending pool.
///         The token is non-transferable (soulbound) to prevent secondary-market manipulation of
///         protocol health-factor accounting. Burns on full collateral withdrawal.
///         Owner is set to the LendingPool proxy; only the pool may mint or burn.
contract PositionNFT is ERC721, Ownable {
    uint256 private _nextTokenId;

    /// @dev user → tokenId (0 means no active position NFT)
    mapping(address => uint256) public positionOf;

    event PositionMinted(address indexed user, uint256 tokenId);
    event PositionBurned(address indexed user, uint256 tokenId);

    error AlreadyHasPosition(address user);
    error NoPosition(address user);
    error Soulbound();

    constructor(address lendingPool) ERC721("DeFi Position", "DPOS") Ownable(lendingPool) { }

    /// @notice Mint a position NFT for a user (called by LendingPool on first deposit)
    function mint(address user) external onlyOwner {
        if (positionOf[user] != 0) revert AlreadyHasPosition(user);
        unchecked {
            _nextTokenId++;
        }
        uint256 tokenId = _nextTokenId;
        positionOf[user] = tokenId;
        _mint(user, tokenId);
        emit PositionMinted(user, tokenId);
    }

    /// @notice Burn the position NFT for a user (called by LendingPool on full withdrawal)
    function burn(address user) external onlyOwner {
        uint256 tokenId = positionOf[user];
        if (tokenId == 0) revert NoPosition(user);
        positionOf[user] = 0;
        _burn(tokenId);
        emit PositionBurned(user, tokenId);
    }

    // ─── Soulbound: disable transfers ─────────────────────────────────────────

    function transferFrom(address, address, uint256) public pure override {
        revert Soulbound();
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert Soulbound();
    }
}
