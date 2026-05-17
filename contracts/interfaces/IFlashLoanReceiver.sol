// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IFlashLoanReceiver
/// @notice Interface for contracts that receive flash loans from LendingPoolV2
/// @dev Implementors must repay the loan + fee within the same transaction
interface IFlashLoanReceiver {
    /// @notice Called by the pool after transferring tokens; must repay amount + fee
    /// @param token     The token that was lent
    /// @param amount    The amount lent
    /// @param fee       The fee due (on top of amount)
    /// @param initiator The address that initiated the flash loan
    /// @param params    Arbitrary data passed through by the caller
    /// @return True if execution was successful
    function onFlashLoan(address token, uint256 amount, uint256 fee, address initiator, bytes calldata params)
        external
        returns (bool);
}
