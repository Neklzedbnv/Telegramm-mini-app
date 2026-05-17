// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IOracle
/// @notice Price oracle interface for the DeFi lending protocol
/// @dev Implementations must return prices normalized to 1e18 (WAD) precision
interface IOracle {
    /// @notice Returns the price of a token in USD, normalized to 18 decimals
    /// @param token The ERC20 token address to price
    /// @return price   USD price scaled to 1e18 (WAD)
    /// @return updatedAt Unix timestamp of the last price update
    function getPrice(address token) external view returns (uint256 price, uint256 updatedAt);
}
