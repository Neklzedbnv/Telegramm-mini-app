// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";

/// @title YieldVault
/// @notice Production-grade ERC-4626 tokenized yield vault integrated with LendingPoolV1
/// @dev Design principles:
///      • ERC-4626 compliance: deposit/mint/withdraw/redeem with standard share accounting
///      • AccessControl: ADMIN_ROLE for critical ops, MANAGER_ROLE for yield operations
///      • Pausable: ADMIN_ROLE can halt all user-facing functions in emergencies
///      • ReentrancyGuard: all external state-changing functions
///      • totalAssets() = underlying balance + accrued yield (simulated lending income)
///      • Shares are never worth less than 1:1 at genesis (first depositor sets the rate)
///
/// Roles:
///   DEFAULT_ADMIN_ROLE — pause, unpause, set lending pool, grant/revoke roles
///   MANAGER_ROLE       — accrue yield, deposit to / withdraw from lending pool
contract YieldVault is ERC4626, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Roles ────────────────────────────────────────────────────────────────

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice The integrated lending pool (may be address(0) if not set)
    ILendingPool public lendingPool;

    /// @notice Accumulated yield credited to the vault (increases totalAssets)
    uint256 public accruedYield;

    /// @notice Total assets deposited into the lending pool on behalf of this vault
    uint256 public deployedAssets;

    // ─── Events ───────────────────────────────────────────────────────────────

    event YieldAccrued(address indexed by, uint256 amount);
    event LendingPoolUpdated(address indexed oldPool, address indexed newPool);
    event AssetsDeployedToPool(uint256 amount);
    event AssetsWithdrawnFromPool(uint256 amount);

    // ─── Errors ───────────────────────────────────────────────────────────────

    error ZeroAmount();
    error ZeroAddress();
    error InsufficientDeployedAssets(uint256 deployed, uint256 requested);
    error LendingPoolNotSet();

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @param asset_       The underlying ERC20 token (e.g. USDC)
    /// @param lendingPool_ The LendingPool to deploy vault assets into (may be address(0))
    /// @param admin        Address that receives DEFAULT_ADMIN_ROLE and MANAGER_ROLE
    constructor(IERC20 asset_, address lendingPool_, address admin)
        ERC4626(asset_)
        ERC20("DeFi Yield Vault", "dyVAULT")
    {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
        if (lendingPool_ != address(0)) {
            lendingPool = ILendingPool(lendingPool_);
        }
    }

    // ─── ERC-4626 Core Overrides ──────────────────────────────────────────────

    /// @notice Returns total assets under management (vault balance + accrued yield + deployed)
    /// @dev This is the single source of truth for share price calculation
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + accruedYield + deployedAssets;
    }

    /// @notice Deposit underlying assets and receive shares
    /// @param assets   Amount of underlying tokens to deposit
    /// @param receiver Address that will receive the vault shares
    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();
        return super.deposit(assets, receiver);
    }

    /// @notice Mint a specific number of shares by providing the required underlying assets
    /// @param shares   Number of shares to mint
    /// @param receiver Address that will receive the vault shares
    function mint(uint256 shares, address receiver)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroAmount();
        return super.mint(shares, receiver);
    }

    /// @notice Withdraw a specific amount of underlying assets by burning shares
    /// @param assets   Amount of underlying tokens to withdraw
    /// @param receiver Address that will receive the withdrawn tokens
    /// @param owner    Address whose shares will be burned
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();
        return super.withdraw(assets, receiver, owner);
    }

    /// @notice Redeem shares for underlying assets
    /// @param shares   Number of shares to redeem
    /// @param receiver Address that will receive the underlying tokens
    /// @param owner    Address whose shares will be burned
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroAmount();
        return super.redeem(shares, receiver, owner);
    }

    // ─── Admin Functions ──────────────────────────────────────────────────────

    /// @notice Pause all deposits, mints, withdrawals, and redeems
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause vault operations
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Update the integrated lending pool address
    function setLendingPool(address pool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address old = address(lendingPool);
        lendingPool = ILendingPool(pool);
        emit LendingPoolUpdated(old, pool);
    }

    // ─── Manager Functions ────────────────────────────────────────────────────

    /// @notice Simulate yield income (in production: replaced by real lending interest)
    /// @dev Increases totalAssets(), which raises the share price for all holders
    function accrueYield(uint256 amount) external onlyRole(MANAGER_ROLE) {
        if (amount == 0) revert ZeroAmount();
        accruedYield += amount;
        emit YieldAccrued(msg.sender, amount);
    }

    /// @notice Deploy vault assets to the lending pool to earn lending interest
    /// @param amount Number of underlying tokens to deposit into the pool
    function deployToLendingPool(uint256 amount) external onlyRole(MANAGER_ROLE) nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (address(lendingPool) == address(0)) revert LendingPoolNotSet();

        address underlying = asset();
        IERC20(underlying).forceApprove(address(lendingPool), amount);
        lendingPool.deposit(underlying, amount);
        deployedAssets += amount;

        emit AssetsDeployedToPool(amount);
    }

    /// @notice Recall assets from the lending pool back to the vault
    /// @param amount Number of underlying tokens to withdraw from the pool
    function recallFromLendingPool(uint256 amount) external onlyRole(MANAGER_ROLE) nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (address(lendingPool) == address(0)) revert LendingPoolNotSet();
        if (amount > deployedAssets) revert InsufficientDeployedAssets(deployedAssets, amount);

        lendingPool.withdraw(asset(), amount);
        deployedAssets -= amount;

        emit AssetsWithdrawnFromPool(amount);
    }

    // ─── ERC165 ───────────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
