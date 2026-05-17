// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ILendingPool
/// @notice Core interface for the DeFi lending pool
interface ILendingPool {
    // ─── Events ───────────────────────────────────────────────────────────────

    event Deposited(address indexed user, address indexed token, uint256 amount);
    event Borrowed(address indexed user, address indexed token, uint256 amount);
    event Repaid(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    event Liquidated(
        address indexed liquidator,
        address indexed borrower,
        address indexed collateralToken,
        address debtToken,
        uint256 debtRepaid,
        uint256 collateralSeized
    );
    event TokenAdded(address indexed token);
    event OracleUpdated(address indexed newOracle);

    // ─── Core Functions ───────────────────────────────────────────────────────

    /// @notice Deposit collateral into the pool
    function deposit(address token, uint256 amount) external;

    /// @notice Borrow tokens against deposited collateral
    function borrow(address token, uint256 amount) external;

    /// @notice Repay outstanding debt
    function repay(address token, uint256 amount) external;

    /// @notice Withdraw collateral from the pool
    function withdraw(address token, uint256 amount) external;

    /// @notice Liquidate an undercollateralized position
    function liquidate(address borrower, address collateralToken, address debtToken, uint256 debtAmount) external;

    // ─── View Functions ───────────────────────────────────────────────────────

    /// @notice Returns the health factor of a user (1e18 = 1.0)
    function healthFactor(address user) external view returns (uint256);

    /// @notice Returns collateral balance for a user/token pair
    function getCollateral(address user, address token) external view returns (uint256);

    /// @notice Returns debt balance for a user/token pair
    function getDebt(address user, address token) external view returns (uint256);

    /// @notice Returns the list of all supported tokens
    function getTokenList() external view returns (address[] memory);
}
