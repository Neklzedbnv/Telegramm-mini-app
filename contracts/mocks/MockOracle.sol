// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IOracle } from "../interfaces/IOracle.sol";

/// @title MockOracle
/// @notice Configurable price oracle for unit / invariant testing
/// @dev Prices are set manually; updatedAt defaults to block.timestamp (always fresh).
///      Use setTimestamp() to simulate stale prices in tests.
contract MockOracle is IOracle {
    mapping(address => uint256) private _prices;

    /// @dev 0 means "use current block.timestamp"; non-zero = fixed stale timestamp
    mapping(address => uint256) private _timestamps;

    event PriceSet(address indexed token, uint256 price);

    function setPrice(address token, uint256 price) external {
        _prices[token] = price;
        emit PriceSet(token, price);
    }

    /// @notice Override the timestamp for a token (0 = reset to always-fresh block.timestamp)
    function setTimestamp(address token, uint256 timestamp) external {
        _timestamps[token] = timestamp;
    }

    /// @notice Returns the token price; updatedAt is current timestamp unless overridden
    function getPrice(address token) external view override returns (uint256 price, uint256 updatedAt) {
        price = _prices[token];
        uint256 ts = _timestamps[token];
        updatedAt = ts == 0 ? block.timestamp : ts;
    }
}
