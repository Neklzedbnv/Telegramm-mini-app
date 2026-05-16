// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./LendingPool.sol";

/// @title LendingPool V2 — demonstrates UUPS upgrade path V1 → V2
contract LendingPoolV2 is LendingPool {
    event FlashLoanExecuted(address indexed token, uint256 amount, address indexed recipient);

    error FlashLoanNotImplemented();

    /// @dev Placeholder flash loan — demonstrates V2 feature addition
    function flashLoan(address, uint256, address) external pure {
        revert FlashLoanNotImplemented();
    }

    function version() external pure override returns (string memory) {
        return "2.0.0";
    }
}
