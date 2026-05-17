// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IFlashLoanReceiver } from "../interfaces/IFlashLoanReceiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MockFlashLoanReceiver
/// @notice Test receiver that correctly repays flash loans; toggle for failure tests
contract MockFlashLoanReceiver is IFlashLoanReceiver {
    using SafeERC20 for IERC20;

    address public immutable lendingPool;
    bool public shouldRepay;
    uint256 public lastAmount;
    uint256 public lastFee;

    constructor(address pool) {
        lendingPool = pool;
        shouldRepay = true;
    }

    function setShouldRepay(bool value) external {
        shouldRepay = value;
    }

    function onFlashLoan(address token, uint256 amount, uint256 fee, address, bytes calldata)
        external
        override
        returns (bool)
    {
        lastAmount = amount;
        lastFee = fee;
        if (shouldRepay) {
            IERC20(token).safeTransfer(lendingPool, amount + fee);
        }
        return shouldRepay;
    }
}
