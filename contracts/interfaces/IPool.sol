// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPool
/// @notice Minimal interface used by the PoolFactory to track deployed pools
interface IPool {
    function version() external pure returns (string memory);
    function initialize(address oracle, address owner) external;
}
