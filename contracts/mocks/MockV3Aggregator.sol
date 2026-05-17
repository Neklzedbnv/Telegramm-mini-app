// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../oracle/interfaces/AggregatorV3Interface.sol";

/// @title MockV3Aggregator
/// @notice Drop-in Chainlink aggregator mock for testing OracleLib and ChainlinkOracleAdapter
/// @dev Mirrors the real Chainlink MockV3Aggregator contract from the Chainlink repo
contract MockV3Aggregator is AggregatorV3Interface {
    // ─── State ────────────────────────────────────────────────────────────────

    uint8 public override decimals;
    string public override description;
    uint256 public override version = 4;

    uint80 public latestRound;
    int256 public latestAnswer;
    uint256 public latestTimestamp;
    uint256 public latestStartedAt;

    mapping(uint80 => int256) public answers;
    mapping(uint80 => uint256) public timestamps;
    mapping(uint80 => uint256) public startedAts;

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @param _decimals       Number of decimals for the price (8 for USD feeds)
    /// @param _initialAnswer  Starting price in feed's native decimals
    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        description = "Mock Price Feed";
        _updateAnswer(_initialAnswer);
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    /// @notice Update the latest answer (timestamp = block.timestamp)
    function updateAnswer(int256 _answer) external {
        _updateAnswer(_answer);
    }

    /// @notice Manually set round data — useful for simulating stale prices
    /// @param _roundId    The round ID to set
    /// @param _answer     The price for this round
    /// @param _timestamp  The updatedAt timestamp (set in the past to simulate staleness)
    /// @param _startedAt  The startedAt timestamp
    function updateRoundData(uint80 _roundId, int256 _answer, uint256 _timestamp, uint256 _startedAt) external {
        latestRound = _roundId;
        latestAnswer = _answer;
        latestTimestamp = _timestamp;
        latestStartedAt = _startedAt;

        answers[_roundId] = _answer;
        timestamps[_roundId] = _timestamp;
        startedAts[_roundId] = _startedAt;
    }

    // ─── AggregatorV3Interface ────────────────────────────────────────────────

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, answers[_roundId], startedAts[_roundId], timestamps[_roundId], _roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (latestRound, latestAnswer, latestStartedAt, latestTimestamp, latestRound);
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    function _updateAnswer(int256 _answer) internal {
        latestRound++;
        latestAnswer = _answer;
        latestTimestamp = block.timestamp;
        latestStartedAt = block.timestamp;

        answers[latestRound] = _answer;
        timestamps[latestRound] = block.timestamp;
        startedAts[latestRound] = block.timestamp;
    }
}
