// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/// @title OracleLib
/// @notice Library for safe interaction with Chainlink price feed aggregators
/// @dev Wraps latestRoundData with staleness detection and 18-decimal normalization.
///      Use this library as the oracle layer instead of calling aggregators directly.
library OracleLib {
    // ─── Constants ────────────────────────────────────────────────────────────

    /// @dev Maximum age of an oracle answer before it is considered stale
    uint256 public constant STALE_TIMEOUT = 3 hours;

    // ─── Errors ───────────────────────────────────────────────────────────────

    /// @notice Thrown when the feed has not been updated within STALE_TIMEOUT
    error StalePrice(address feed, uint256 updatedAt);

    /// @notice Thrown when the feed returns a non-positive answer
    error InvalidPrice(address feed, int256 answer);

    /// @notice Thrown when round data is incomplete (answeredInRound < roundId)
    error IncompleteRound(address feed, uint80 roundId, uint80 answeredInRound);

    // ─── Library Functions ────────────────────────────────────────────────────

    /// @notice Reads latest round data from a Chainlink feed, reverting on stale/invalid data
    /// @param feed The Chainlink AggregatorV3Interface to query
    /// @return roundId          The round ID
    /// @return answer           The raw price answer (in feed's native decimals)
    /// @return startedAt        Timestamp when the round started
    /// @return updatedAt        Timestamp of the last price update
    /// @return answeredInRound  The round in which the answer was computed
    function staleCheckLatestRoundData(AggregatorV3Interface feed)
        internal
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = feed.latestRoundData();

        // Stale round: the answer was computed in a different (older) round
        if (answeredInRound < roundId) {
            revert IncompleteRound(address(feed), roundId, answeredInRound);
        }

        // Zero updatedAt means the round was never completed
        if (updatedAt == 0) revert StalePrice(address(feed), updatedAt);

        // Price is older than our tolerance window
        unchecked {
            // safe: block.timestamp >= updatedAt always (monotonic clock)
            if (block.timestamp - updatedAt > STALE_TIMEOUT) {
                revert StalePrice(address(feed), updatedAt);
            }
        }

        // Non-positive price is nonsensical for an asset price
        if (answer <= 0) revert InvalidPrice(address(feed), answer);
    }

    /// @notice Reads price and normalizes it to 18 decimal WAD format
    /// @param feed     The Chainlink feed to query
    /// @return price   The price in WAD (18 decimals), > 0
    /// @return updatedAt Unix timestamp of the price update
    function getWadPrice(AggregatorV3Interface feed) internal view returns (uint256 price, uint256 updatedAt) {
        (, int256 answer,, uint256 ts,) = staleCheckLatestRoundData(feed);
        uint8 dec = feed.decimals();
        price = normalizeToWad(answer, dec);
        updatedAt = ts;
    }

    /// @notice Normalizes a Chainlink answer from its native decimals to 18-decimal WAD
    /// @dev Uses inline assembly for gas efficiency — avoids Solidity division overhead
    ///      for the common case where dec < 18 (most Chainlink feeds use 8 decimals).
    /// @param answer   The raw int256 answer from the feed (must be positive)
    /// @param dec      The number of decimals used by the feed
    /// @return result  The answer scaled to 1e18
    function normalizeToWad(int256 answer, uint8 dec) internal pure returns (uint256 result) {
        // Cast to uint256 here — callers guarantee answer > 0
        uint256 raw;
        assembly {
            // sign-extend int256 → uint256 (safe because answer > 0)
            raw := answer
        }

        if (dec == 18) {
            return raw;
        }

        assembly {
            switch lt(dec, 18)
            case 1 {
                // dec < 18 → multiply up: result = raw * 10^(18-dec)
                let diff := sub(18, dec)
                let multiplier := exp(10, diff)
                result := mul(raw, multiplier)
            }
            default {
                // dec > 18 → divide down: result = raw / 10^(dec-18)
                let diff := sub(dec, 18)
                let divisor := exp(10, diff)
                result := div(raw, divisor)
            }
        }
    }

    /// @notice Computes the CREATE2 address for a contract — assembly-optimized utility
    /// @dev Equivalent to OZ Create2.computeAddress but avoids external library call overhead
    /// @param salt          The 32-byte salt
    /// @param bytecodeHash  keccak256 of the creation bytecode
    /// @param deployer      The address that will call CREATE2
    /// @return predicted    The deterministic deployment address
    function computeCreate2Address(bytes32 salt, bytes32 bytecodeHash, address deployer)
        internal
        pure
        returns (address predicted)
    {
        assembly {
            // Layout: 0xff ++ deployer(20) ++ salt(32) ++ bytecodeHash(32) = 85 bytes
            let ptr := mload(0x40)
            mstore8(ptr, 0xff)
            mstore(add(ptr, 0x01), shl(96, deployer)) // right-aligned 20-byte address
            mstore(add(ptr, 0x15), salt)
            mstore(add(ptr, 0x35), bytecodeHash)
            predicted := and(keccak256(ptr, 0x55), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }
}
