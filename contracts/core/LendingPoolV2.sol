// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LendingPoolV1} from "./LendingPoolV1.sol";
import {IFlashLoanReceiver} from "../interfaces/IFlashLoanReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title LendingPoolV2
/// @notice LendingPoolV1 upgraded with flash loan functionality
/// @dev Demonstrates the UUPS upgrade path: V1 → V2.
///      All V1 state is preserved through the proxy; V2 adds:
///        • flash loans with configurable fee
///        • flash loan fee treasury
///        • flash loan guards (nonReentrant from V1's ReentrancyGuard)
///
/// Upgrade procedure:
///   1. Deploy LendingPoolV2 implementation
///   2. Call proxy.upgradeToAndCall(address(v2Impl), "")  — authorized by owner
///   3. Optionally call v2.setFlashLoanFee(newFee) if changing defaults
contract LendingPoolV2 is LendingPoolV1 {
    using SafeERC20 for IERC20;

    // ─── New State (appended after V1 storage) ────────────────────────────────

    /// @notice Fee charged on flash loans in basis points (1 = 0.01%)
    uint256 public flashLoanFeeBps;

    /// @notice Accumulated flash loan fees, claimable by the owner
    mapping(address => uint256) public flashLoanFees;

    // ─── Events ───────────────────────────────────────────────────────────────

    event FlashLoanExecuted(
        address indexed token, uint256 amount, uint256 fee, address indexed receiver, address indexed initiator
    );
    event FlashLoanFeeUpdated(uint256 oldFee, uint256 newFee);
    event FlashLoanFeesWithdrawn(address indexed token, uint256 amount, address indexed recipient);

    // ─── Errors ───────────────────────────────────────────────────────────────

    error FlashLoanNotRepaid(uint256 expected, uint256 actual);
    error FlashLoanCallbackFailed();
    error FeeTooHigh(uint256 feeBps, uint256 maxBps);
    error TokenNotSupportedForFlashLoan(address token);

    // ─── V2 Initializer (called via upgradeToAndCall if needed) ───────────────

    /// @notice Initialize new V2 state; safe to call during upgrade via upgradeToAndCall
    /// @dev Uses reinitializer(2) so it runs exactly once on this version
    function initializeV2(uint256 feeBps) external reinitializer(2) {
        if (feeBps > 500) revert FeeTooHigh(feeBps, 500); // max 5%
        flashLoanFeeBps = feeBps;
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    /// @notice Set the flash loan fee (owner only)
    /// @param feeBps New fee in basis points (max 500 = 5%)
    function setFlashLoanFee(uint256 feeBps) external onlyOwner {
        if (feeBps > 500) revert FeeTooHigh(feeBps, 500);
        emit FlashLoanFeeUpdated(flashLoanFeeBps, feeBps);
        flashLoanFeeBps = feeBps;
    }

    /// @notice Withdraw accumulated flash loan fees
    function withdrawFlashLoanFees(address token, address recipient) external onlyOwner {
        uint256 amount = flashLoanFees[token];
        flashLoanFees[token] = 0;
        IERC20(token).safeTransfer(recipient, amount);
        emit FlashLoanFeesWithdrawn(token, amount, recipient);
    }

    // ─── Flash Loan ───────────────────────────────────────────────────────────

    /// @notice Execute a flash loan: lend `amount` of `token` to `receiver`, expect repayment + fee
    /// @dev Flow:
    ///      1. Validate token is supported and pool has liquidity
    ///      2. Transfer `amount` to receiver
    ///      3. Call receiver.onFlashLoan(token, amount, fee, msg.sender, params)
    ///      4. Verify pool balance increased by `amount + fee`
    ///      5. Account for the fee
    /// @param token    The ERC20 token to flash-lend
    /// @param amount   The amount to lend
    /// @param receiver Contract that implements IFlashLoanReceiver
    /// @param params   Arbitrary data forwarded to the receiver
    function flashLoan(address token, uint256 amount, address receiver, bytes calldata params)
        external
        nonReentrant
    {
        if (!supportedTokens[token]) revert TokenNotSupportedForFlashLoan(token);
        if (amount == 0) revert ZeroAmount();

        uint256 available = totalDeposits[token] - totalBorrows[token];
        if (available < amount) revert InsufficientLiquidity(available, amount);

        uint256 fee = (amount * flashLoanFeeBps) / 10_000;
        uint256 expectedRepayment = amount + fee;

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));

        // Transfer flash loan amount to receiver
        IERC20(token).safeTransfer(receiver, amount);

        // Call receiver callback
        bool success = IFlashLoanReceiver(receiver).onFlashLoan(token, amount, fee, msg.sender, params);
        if (!success) revert FlashLoanCallbackFailed();

        // Verify repayment
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        if (balanceAfter < balanceBefore + fee) {
            revert FlashLoanNotRepaid(balanceBefore + fee, balanceAfter);
        }

        // Accrue the fee
        flashLoanFees[token] += fee;

        emit FlashLoanExecuted(token, amount, fee, receiver, msg.sender);
    }

    // ─── Version ─────────────────────────────────────────────────────────────

    function version() external pure override returns (string memory) {
        return "2.0.0";
    }
}
