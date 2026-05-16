// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ILendingPool.sol";

/// @title LendingPool V1 — UUPS Upgradeable DeFi Lending Protocol
contract LendingPool is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuard,
    ILendingPool
{
    using SafeERC20 for IERC20;

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant PRECISION = 1e18;
    /// @dev LTV 75%: max borrow = 75% of collateral value
    uint256 public constant LTV_RATIO = 75;
    /// @dev Liquidation threshold 80%: liquidatable below this health factor
    uint256 public constant LIQUIDATION_THRESHOLD = 80;
    /// @dev Liquidation bonus 5% for liquidators
    uint256 public constant LIQUIDATION_BONUS = 5;
    /// @dev Minimum health factor (1.0 scaled by PRECISION)
    uint256 public constant MIN_HEALTH_FACTOR = PRECISION;

    // ─── State ───────────────────────────────────────────────────────────────

    IOracle public oracle;

    /// @dev user => token => collateral amount
    mapping(address => mapping(address => uint256)) private _collateral;
    /// @dev user => token => debt amount
    mapping(address => mapping(address => uint256)) private _debt;
    /// @dev token => total deposited
    mapping(address => uint256) public totalDeposits;
    /// @dev token => total borrowed
    mapping(address => uint256) public totalBorrows;
    /// @dev supported collateral tokens
    mapping(address => bool) public supportedTokens;
    address[] public tokenList;

    // ─── Errors ──────────────────────────────────────────────────────────────

    error TokenNotSupported(address token);
    error ZeroAmount();
    error InsufficientLiquidity(uint256 available, uint256 requested);
    error InsufficientCollateral(uint256 collateral, uint256 requested);
    error HealthFactorTooLow(uint256 healthFactor);
    error HealthFactorOk(uint256 healthFactor);
    error InvalidPrice();

    // ─── Initializer ─────────────────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address oracle_, address initialOwner) external initializer {
        __Ownable_init(initialOwner);
        oracle = IOracle(oracle_);
    }

    // ─── Admin ───────────────────────────────────────────────────────────────

    function addSupportedToken(address token) external onlyOwner {
        if (!supportedTokens[token]) {
            supportedTokens[token] = true;
            tokenList.push(token);
        }
    }

    function setOracle(address oracle_) external onlyOwner {
        oracle = IOracle(oracle_);
    }

    // ─── Core Functions ──────────────────────────────────────────────────────

    function deposit(address token, uint256 amount) external nonReentrant {
        if (!supportedTokens[token]) revert TokenNotSupported(token);
        if (amount == 0) revert ZeroAmount();

        // Effects
        _collateral[msg.sender][token] += amount;
        totalDeposits[token] += amount;

        // Interaction
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(msg.sender, token, amount);
    }

    function borrow(address token, uint256 amount) external nonReentrant {
        if (!supportedTokens[token]) revert TokenNotSupported(token);
        if (amount == 0) revert ZeroAmount();

        uint256 available = totalDeposits[token] - totalBorrows[token];
        if (available < amount) revert InsufficientLiquidity(available, amount);

        // Checks — simulate borrow and verify health factor
        _debt[msg.sender][token] += amount;
        totalBorrows[token] += amount;

        uint256 hf = _computeHealthFactor(msg.sender);
        if (hf < MIN_HEALTH_FACTOR) revert HealthFactorTooLow(hf);

        // Interaction
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Borrowed(msg.sender, token, amount);
    }

    function repay(address token, uint256 amount) external nonReentrant {
        if (!supportedTokens[token]) revert TokenNotSupported(token);
        if (amount == 0) revert ZeroAmount();

        uint256 debt = _debt[msg.sender][token];
        // Cap repay at actual debt
        uint256 repayAmount = amount > debt ? debt : amount;

        // Effects
        _debt[msg.sender][token] -= repayAmount;
        totalBorrows[token] -= repayAmount;

        // Interaction
        IERC20(token).safeTransferFrom(msg.sender, address(this), repayAmount);

        emit Repaid(msg.sender, token, repayAmount);
    }

    function withdraw(address token, uint256 amount) external nonReentrant {
        if (!supportedTokens[token]) revert TokenNotSupported(token);
        if (amount == 0) revert ZeroAmount();

        uint256 col = _collateral[msg.sender][token];
        if (col < amount) revert InsufficientCollateral(col, amount);

        // Simulate withdrawal and check health factor
        _collateral[msg.sender][token] -= amount;
        totalDeposits[token] -= amount;

        uint256 hf = _computeHealthFactor(msg.sender);
        if (hf < MIN_HEALTH_FACTOR) revert HealthFactorTooLow(hf);

        // Interaction
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, token, amount);
    }

    function liquidate(address borrower, address collateralToken, address debtToken, uint256 debtAmount)
        external
        nonReentrant
    {
        if (!supportedTokens[collateralToken]) revert TokenNotSupported(collateralToken);
        if (!supportedTokens[debtToken]) revert TokenNotSupported(debtToken);
        if (debtAmount == 0) revert ZeroAmount();

        uint256 hf = _computeHealthFactor(borrower);
        if (hf >= MIN_HEALTH_FACTOR) revert HealthFactorOk(hf);

        uint256 actualDebt = _debt[borrower][debtToken];
        uint256 repayAmount = debtAmount > actualDebt ? actualDebt : debtAmount;

        // Calculate collateral to seize (debt value + liquidation bonus)
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

    function _computeHealthFactor(address user) internal view returns (uint256 hf) {
        uint256 totalCollateralValue;
        uint256 totalDebtValue;

        uint256 len = tokenList.length;
        for (uint256 i; i < len;) {
            address token = tokenList[i];
            uint256 col = _collateral[user][token];
            uint256 dbt = _debt[user][token];

            if (col > 0) {
                totalCollateralValue += _tokenValue(token, col);
            }
            if (dbt > 0) {
                totalDebtValue += _tokenValue(token, dbt);
            }

            unchecked {
                ++i;
            }
        }

        if (totalDebtValue == 0) return type(uint256).max;

        // health factor = (collateral * liquidationThreshold / 100) / debt
        // Using inline assembly for gas optimization
        assembly {
            let collateralWeighted := div(mul(totalCollateralValue, 80), 100)
            hf := div(mul(collateralWeighted, PRECISION), totalDebtValue)
        }
    }

    function _tokenValue(address token, uint256 amount) internal view returns (uint256) {
        uint256 price = _getPrice(token);
        return (amount * price) / PRECISION;
    }

    function _getPrice(address token) internal view returns (uint256 price) {
        uint256 updatedAt;
        (price, updatedAt) = oracle.getPrice(token);
        if (price == 0) revert InvalidPrice();
        // Staleness check: reject prices older than 1 hour
        // (for Chainlink integration by Nikita)
        if (block.timestamp - updatedAt > 1 hours) revert InvalidPrice();
    }

    // ─── UUPS ─────────────────────────────────────────────────────────────────

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ─── Version ─────────────────────────────────────────────────────────────

    function version() external pure virtual returns (string memory) {
        return "1.0.0";
    }
}
