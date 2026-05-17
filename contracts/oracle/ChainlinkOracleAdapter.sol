// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OracleLib } from "./OracleLib.sol";
import { AggregatorV3Interface } from "./interfaces/AggregatorV3Interface.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ChainlinkOracleAdapter
/// @notice Adapts Chainlink price feeds to the IOracle interface used by LendingPoolV1
/// @dev Registers a feed per token; uses OracleLib for staleness checks and WAD normalization
contract ChainlinkOracleAdapter is IOracle, Ownable {
    using OracleLib for AggregatorV3Interface;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Chainlink feed for each token
    mapping(address => AggregatorV3Interface) public feeds;

    // ─── Events ───────────────────────────────────────────────────────────────

    event FeedSet(address indexed token, address indexed feed);

    // ─── Errors ───────────────────────────────────────────────────────────────

    error FeedNotSet(address token);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address initialOwner) Ownable(initialOwner) { }

    // ─── Admin ────────────────────────────────────────────────────────────────

    /// @notice Register a Chainlink feed for a token
    /// @param token The ERC20 token address
    /// @param feed  The Chainlink AggregatorV3Interface address
    function setFeed(address token, address feed) external onlyOwner {
        feeds[token] = AggregatorV3Interface(feed);
        emit FeedSet(token, feed);
    }

    // ─── IOracle Implementation ───────────────────────────────────────────────

    /// @notice Returns the WAD-normalized price for a token via Chainlink
    /// @dev Reverts with OracleLib errors on stale/invalid data
    function getPrice(address token) external view override returns (uint256 price, uint256 updatedAt) {
        AggregatorV3Interface feed = feeds[token];
        if (address(feed) == address(0)) revert FeedNotSet(token);
        (price, updatedAt) = feed.getWadPrice();
    }
}
