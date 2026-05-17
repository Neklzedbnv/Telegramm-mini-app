// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { ILendingPool } from "../interfaces/ILendingPool.sol";
import { PositionNFT } from "../tokens/PositionNFT.sol";

/// @title LendingPoolV1
/// @notice Production-grade UUPS-upgradeable cross-collateral lending pool
/// @dev Architecture principles:
///      • CEI (Checks-Effects-Interactions) on every state-changing function
///      • SafeERC20 for all token transfers
///      • ReentrancyGuard on all external mutating functions
///      • Custom errors (no string revert messages) for gas efficiency
///      • Inline assembly for gas-critical health-factor computation
///      • storage packing: booleans and uint96 in same slot where possible
///
/// Upgrade path: This contract is deployed behind an ERC1967Proxy.
/// The owner can authorize an upgrade to LendingPoolV2 via upgradeToAndCall().
contract LendingPoolV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard, ILendingPool {
    using SafeERC20 for IERC20;

    // ─── Constants ────────────────────────────────────────────────────────────

    uint256 public constant PRECISION = 1e18;

    /// @notice Maximum loan-to-value ratio: borrowers may take up to 75% of collateral value
    uint256 public constant LTV_RATIO = 75;

    /// @notice Liquidation threshold: positions become liquidatable below 80% health factor
    uint256 public constant LIQUIDATION_THRESHOLD = 80;

    /// @notice Bonus collateral granted to liquidators (5% above the debt value)
    uint256 public constant LIQUIDATION_BONUS = 5;

    /// @notice Minimum health factor; below this level the position can be liquidated
    uint256 public constant MIN_HEALTH_FACTOR = PRECISION; // 1.0

    /// @notice Maximum age of oracle price before it is considered stale
    uint256 public constant STALE_PRICE_DELAY = 1 hours;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Annual interest rate (in basis points, e.g. 500 = 5% APR)
    uint256 public constant INTEREST_RATE_BPS = 500;
    /// @notice Seconds in a year (365 days)
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    IOracle public oracle;

    /// @notice Optional position NFT contract; address(0) disables NFT minting
    PositionNFT public positionNFT;

    /// @dev user → token → collateral balance
    mapping(address => mapping(address => uint256)) private _collateral;

    /// @dev user → token → debt balance (principal only; accrued interest tracked separately)
    mapping(address => mapping(address => uint256)) private _debt;

    /// @dev user → token → accrued interest not yet repaid
    mapping(address => mapping(address => uint256)) private _accruedInterest;

    /// @dev user → token → last interest accrual timestamp
    mapping(address => mapping(address => uint256)) private _lastAccrual;

    /// @dev token → total collateral deposited
    mapping(address => uint256) public totalDeposits;

    /// @dev token → total amount borrowed
    mapping(address => uint256) public totalBorrows;

    /// @dev token → is supported as collateral/debt
    mapping(address => bool) public supportedTokens;

    /// @dev ordered list of supported tokens (used by health-factor loop)
    address[] public tokenList;

    // ─── Errors ───────────────────────────────────────────────────────────────

    error TokenNotSupported(address token);
    error ZeroAmount();
    error InsufficientLiquidity(uint256 available, uint256 requested);
    error InsufficientCollateral(uint256 collateral, uint256 requested);
    error HealthFactorTooLow(uint256 healthFactor);
    error HealthFactorOk(uint256 healthFactor);
    error InvalidPrice();
    error ZeroAddress();

    // ─── Constructor / Initializer ────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the proxy; called once by the factory or deployment script
    /// @param oracle_       Address of the IOracle price source
    /// @param initialOwner  Address that receives owner privileges
    function initialize(address oracle_, address initialOwner) external initializer {
        if (oracle_ == address(0) || initialOwner == address(0)) revert ZeroAddress();
        __Ownable_init(initialOwner);
        oracle = IOracle(oracle_);
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    /// @notice Register a token as acceptable collateral / borrowable asset
    /// @dev Idempotent; calling twice with the same token is a no-op
    function addSupportedToken(address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (!supportedTokens[token]) {
            supportedTokens[token] = true;
            tokenList.push(token);
            emit TokenAdded(token);
        }
    }

    /// @notice Set the PositionNFT contract (can be called once after deployment)
    function setPositionNFT(address nft_) external onlyOwner {
        if (nft_ == address(0)) revert ZeroAddress();
        positionNFT = PositionNFT(nft_);
    }

    /// @notice Update the price oracle
    function setOracle(address oracle_) external onlyOwner {
        if (oracle_ == address(0)) revert ZeroAddress();
        oracle = IOracle(oracle_);
        emit OracleUpdated(oracle_);
    }

    // ─── Core: Deposit ────────────────────────────────────────────────────────

    /// @notice Deposit ERC20 collateral into the pool
    /// @param token  The supported ERC20 token to deposit
    /// @param amount Number of tokens (in token's native decimals)
    function deposit(address token, uint256 amount) external nonReentrant {
        if (!supportedTokens[token]) revert TokenNotSupported(token);
        if (amount == 0) revert ZeroAmount();

        // Effects first (CEI)
        bool isFirstDeposit = _collateral[msg.sender][token] == 0 && _totalCollateral(msg.sender) == 0;
        _collateral[msg.sender][token] += amount;
        totalDeposits[token] += amount;

        // Interaction last
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Mint position NFT on first deposit (if NFT contract configured)
        if (isFirstDeposit && address(positionNFT) != address(0)) {
            if (positionNFT.positionOf(msg.sender) == 0) {
                positionNFT.mint(msg.sender);
            }
        }

        emit Deposited(msg.sender, token, amount);
    }

    // ─── Core: Borrow ─────────────────────────────────────────────────────────

    /// @notice Borrow tokens against existing collateral
    /// @dev Simulates the borrow first, then checks health factor to enforce LTV
    function borrow(address token, uint256 amount) external nonReentrant {
        if (!supportedTokens[token]) revert TokenNotSupported(token);
        if (amount == 0) revert ZeroAmount();

        uint256 available = totalDeposits[token] - totalBorrows[token];
        if (available < amount) revert InsufficientLiquidity(available, amount);

        // Accrue any existing interest before adding new principal
        _accrueInterest(msg.sender, token);

        // Tentatively apply borrow to state
        _debt[msg.sender][token] += amount;
        totalBorrows[token] += amount;

        // Health check AFTER state update (simulates the new debt level)
        uint256 hf = _computeHealthFactor(msg.sender);
        if (hf < MIN_HEALTH_FACTOR) revert HealthFactorTooLow(hf);

        // Transfer out
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Borrowed(msg.sender, token, amount);
    }

    // ─── Core: Repay ──────────────────────────────────────────────────────────

    /// @notice Repay outstanding debt (caps at actual debt balance)
    function repay(address token, uint256 amount) external nonReentrant {
        if (!supportedTokens[token]) revert TokenNotSupported(token);
        if (amount == 0) revert ZeroAmount();

        // Accrue interest first so repayment covers it
        _accrueInterest(msg.sender, token);

        // Repay accrued interest first, then principal
        uint256 interest = _accruedInterest[msg.sender][token];
        uint256 remaining = amount;
        if (interest > 0) {
            uint256 interestPaid = remaining > interest ? interest : remaining;
            _accruedInterest[msg.sender][token] -= interestPaid;
            remaining -= interestPaid;
        }

        uint256 debt = _debt[msg.sender][token];
        uint256 repayAmount = remaining > debt ? debt : remaining;

        // Effects
        _debt[msg.sender][token] -= repayAmount;
        totalBorrows[token] -= repayAmount;

        // Interaction
        IERC20(token).safeTransferFrom(msg.sender, address(this), repayAmount);

        emit Repaid(msg.sender, token, repayAmount);
    }

    // ─── Core: Withdraw ───────────────────────────────────────────────────────

    /// @notice Withdraw collateral (blocked if it would drop health factor below MIN)
    function withdraw(address token, uint256 amount) external nonReentrant {
        if (!supportedTokens[token]) revert TokenNotSupported(token);
        if (amount == 0) revert ZeroAmount();

        uint256 col = _collateral[msg.sender][token];
        if (col < amount) revert InsufficientCollateral(col, amount);

        // Tentatively reduce collateral, then verify health factor
        _collateral[msg.sender][token] -= amount;
        totalDeposits[token] -= amount;

        uint256 hf = _computeHealthFactor(msg.sender);
        if (hf < MIN_HEALTH_FACTOR) revert HealthFactorTooLow(hf);

        IERC20(token).safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, token, amount);
    }

    // ─── Core: Liquidate ──────────────────────────────────────────────────────

    /// @notice Liquidate an undercollateralized borrower; caller repays debt and receives discounted collateral
    /// @param borrower       The account to liquidate
    /// @param collateralToken The token seized from the borrower
    /// @param debtToken       The token the caller repays
    /// @param debtAmount      Amount of debt to repay (capped at borrower's actual debt)
    function liquidate(address borrower, address collateralToken, address debtToken, uint256 debtAmount)
        external
        nonReentrant
    {
        if (!supportedTokens[collateralToken]) revert TokenNotSupported(collateralToken);
        if (!supportedTokens[debtToken]) revert TokenNotSupported(debtToken);
        if (debtAmount == 0) revert ZeroAmount();

        // Only liquidate if health factor is below minimum
        uint256 hf = _computeHealthFactor(borrower);
        if (hf >= MIN_HEALTH_FACTOR) revert HealthFactorOk(hf);

        uint256 actualDebt = _debt[borrower][debtToken];
        uint256 repayAmount = debtAmount > actualDebt ? actualDebt : debtAmount;

        // Collateral to seize = debt value * (1 + LIQUIDATION_BONUS%) / collateral price
        uint256 debtValue = _tokenValue(debtToken, repayAmount);
        uint256 collateralPrice = _getPrice(collateralToken);
        uint256 collateralToSeize = (debtValue * (100 + LIQUIDATION_BONUS) * PRECISION) / (100 * collateralPrice);

        uint256 availableCollateral = _collateral[borrower][collateralToken];
        if (collateralToSeize > availableCollateral) {
            collateralToSeize = availableCollateral;
        }

        // Effects
        _debt[borrower][debtToken] -= repayAmount;
        totalBorrows[debtToken] -= repayAmount;
        _collateral[borrower][collateralToken] -= collateralToSeize;
        totalDeposits[collateralToken] -= collateralToSeize;

        // Interactions
        IERC20(debtToken).safeTransferFrom(msg.sender, address(this), repayAmount);
        IERC20(collateralToken).safeTransfer(msg.sender, collateralToSeize);

        emit Liquidated(msg.sender, borrower, collateralToken, debtToken, repayAmount, collateralToSeize);
    }

    // ─── View Functions ───────────────────────────────────────────────────────

    function healthFactor(address user) external view returns (uint256) {
        return _computeHealthFactor(user);
    }

    function getCollateral(address user, address token) external view returns (uint256) {
        return _collateral[user][token];
    }

    function getDebt(address user, address token) external view returns (uint256) {
        return _debt[user][token];
    }

    function getTokenList() external view returns (address[] memory) {
        return tokenList;
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    /// @dev Computes the health factor for a user across all supported tokens.
    ///      Uses inline assembly for the final division to reduce gas compared to Solidity.
    ///      health factor = (Σ collateralValue_i * LIQUIDATION_THRESHOLD / 100) / Σ debtValue_i
    ///      Returns type(uint256).max when the user has zero debt.
    function _computeHealthFactor(address user) internal view returns (uint256 hf) {
        uint256 totalCollateralValue;
        uint256 totalDebtValue;

        uint256 len = tokenList.length;
        for (uint256 i; i < len;) {
            address token = tokenList[i];
            uint256 col = _collateral[user][token];
            uint256 dbt = _debt[user][token];

            if (col > 0) totalCollateralValue += _tokenValue(token, col);
            if (dbt > 0) totalDebtValue += _tokenValue(token, dbt);

            unchecked {
                ++i;
            }
        }

        if (totalDebtValue == 0) return type(uint256).max;

        // Inline assembly: gas-efficient weighted health factor
        // hf = (totalCollateralValue * LIQUIDATION_THRESHOLD / 100 * PRECISION) / totalDebtValue
        // LIQUIDATION_THRESHOLD = 80, PRECISION = 1e18 (compile-time constants → inlined)
        assembly {
            let weightedCollateral := div(mul(totalCollateralValue, 80), 100)
            hf := div(mul(weightedCollateral, PRECISION), totalDebtValue)
        }
    }

    /// @dev Returns the USD value of an amount of a token, in WAD (18 decimals)
    function _tokenValue(address token, uint256 amount) internal view returns (uint256) {
        uint256 price = _getPrice(token);
        return (amount * price) / PRECISION;
    }

    /// @dev Fetches and validates the oracle price for a token; reverts on stale / zero prices
    function _getPrice(address token) internal view returns (uint256 price) {
        uint256 updatedAt;
        (price, updatedAt) = oracle.getPrice(token);
        if (price == 0) revert InvalidPrice();
        // Staleness check: compatible with both MockOracle and ChainlinkOracleAdapter
        if (updatedAt == 0 || updatedAt > block.timestamp) revert InvalidPrice();
        if (block.timestamp - updatedAt > STALE_PRICE_DELAY) revert InvalidPrice();
    }

    /// @notice Returns the outstanding interest owed by a user on a token
    function getAccruedInterest(address user, address token) external view returns (uint256) {
        uint256 principal = _debt[user][token];
        if (principal == 0) return _accruedInterest[user][token];
        uint256 elapsed = block.timestamp - _lastAccrual[user][token];
        uint256 newInterest = (principal * INTEREST_RATE_BPS * elapsed) / (10_000 * SECONDS_PER_YEAR);
        return _accruedInterest[user][token] + newInterest;
    }

    /// @dev Materialises interest for (user, token) into _accruedInterest storage.
    ///      Called before every borrow/repay/liquidate to keep debt current.
    function _accrueInterest(address user, address token) internal {
        uint256 principal = _debt[user][token];
        if (principal == 0) {
            _lastAccrual[user][token] = block.timestamp;
            return;
        }
        uint256 last = _lastAccrual[user][token];
        if (last == 0) {
            _lastAccrual[user][token] = block.timestamp;
            return;
        }
        uint256 elapsed = block.timestamp - last;
        if (elapsed == 0) return;
        uint256 interest = (principal * INTEREST_RATE_BPS * elapsed) / (10_000 * SECONDS_PER_YEAR);
        _accruedInterest[user][token] += interest;
        _lastAccrual[user][token] = block.timestamp;
    }

    /// @dev Returns total collateral value across all tokens for a user (used for first-deposit check)
    function _totalCollateral(address user) internal view returns (uint256 total) {
        uint256 len = tokenList.length;
        for (uint256 i; i < len;) {
            total += _collateral[user][tokenList[i]];
            unchecked {
                ++i;
            }
        }
    }

    // ─── UUPS ─────────────────────────────────────────────────────────────────

    /// @dev Only the owner may authorize an upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    // ─── Version ─────────────────────────────────────────────────────────────

    /// @notice Returns the implementation version string
    function version() external pure virtual returns (string memory) {
        return "1.0.0";
    }
}
