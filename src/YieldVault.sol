// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ILendingPool.sol";

/// @title YieldVault — ERC-4626 compliant vault integrating with LendingPool
contract YieldVault is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    ILendingPool public lendingPool;
    uint256 public accruedYield;

    event YieldAccrued(uint256 amount);
    event LendingPoolUpdated(address newPool);

    constructor(IERC20 asset_, address lendingPool_, address initialOwner)
        ERC4626(asset_)
        ERC20("DeFi Yield Vault", "dyVAULT")
        Ownable(initialOwner)
    {
        lendingPool = ILendingPool(lendingPool_);
    }

    // ─── ERC-4626 overrides ───────────────────────────────────────────────────

    /// @dev totalAssets includes vault balance + simulated accrued yield
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + accruedYield;
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    function setLendingPool(address pool) external onlyOwner {
        lendingPool = ILendingPool(pool);
        emit LendingPoolUpdated(pool);
    }

    /// @dev Simulate yield accrual (in production: from interest income of LendingPool)
    function accrueYield(uint256 amount) external onlyOwner {
        accruedYield += amount;
        emit YieldAccrued(amount);
    }

    /// @dev Deposit vault funds into LendingPool to earn yield
    function depositToLendingPool(uint256 amount) external onlyOwner {
        address token = asset();
        IERC20(token).forceApprove(address(lendingPool), amount);
        lendingPool.deposit(token, amount);
    }

    /// @dev Withdraw vault funds from LendingPool
    function withdrawFromLendingPool(uint256 amount) external onlyOwner {
        lendingPool.withdraw(asset(), amount);
    }
}
