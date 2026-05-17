// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AggregatorV3Interface
/// @notice Chainlink aggregator interface for reading on-chain price feeds
/// @dev Matches Chainlink's published ABI exactly
interface AggregatorV3Interface {
    /// @notice Returns the number of decimals in the aggregator's answer
    function decimals() external view returns (uint8);

    /// @notice Human-readable description of the aggregator
    function description() external view returns (string memory);

    /// @notice Version of the aggregator interface
    function version() external view returns (uint256);

    /// @notice Returns data for a specific round
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /// @notice Returns data for the most recent round
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
