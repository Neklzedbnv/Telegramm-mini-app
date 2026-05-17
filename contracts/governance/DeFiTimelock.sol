// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title DeFiTimelock
/// @notice TimelockController with a 2-day minimum delay governing protocol admin actions.
///         Deployed as the owner of LendingPool, YieldVault, and DeFiToken so that
///         all privileged operations must pass through governance before execution.
contract DeFiTimelock is TimelockController {
    /// @param minDelay   Minimum delay before a queued action can execute (2 days = 172800 s)
    /// @param proposers  Addresses allowed to schedule (typically the Governor contract)
    /// @param executors  Addresses allowed to execute (address(0) = anyone)
    /// @param admin      Initial admin; should be renounced after setup
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    { }
}
