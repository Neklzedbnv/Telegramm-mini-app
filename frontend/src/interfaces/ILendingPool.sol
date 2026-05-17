// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILendingPool {
    event Deposited(address indexed user, address indexed token, uint256 amount);
    event Borrowed(address indexed user, address indexed token, uint256 amount);
    event Repaid(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    event Liquidated(
        address indexed liquidator,
        address indexed borrower,
        address indexed collateralToken,
        address debtToken,
        uint256 debtAmount,
        uint256 collateralSeized
    );

    function deposit(address token, uint256 amount) external;
    function borrow(address token, uint256 amount) external;
    function repay(address token, uint256 amount) external;
    function withdraw(address token, uint256 amount) external;
    function liquidate(address borrower, address collateralToken, address debtToken, uint256 debtAmount) external;
    function healthFactor(address user) external view returns (uint256);
    function getCollateral(address user, address token) external view returns (uint256);
    function getDebt(address user, address token) external view returns (uint256);
}
