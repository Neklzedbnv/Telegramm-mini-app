// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AMM — Constant-Product Automated Market Maker (x·y=k)
/// @notice Built from scratch per BChT2 §3.1 DeFi primitive requirement.
///         - 0.3% swap fee (30 bps), retained in reserves (k only grows after swaps)
///         - Slippage protection via minAmountOut parameter
///         - LP tokens: internal ERC20 tracking (totalSupply + balanceOf)
///         - CEI pattern + ReentrancyGuard on all state-changing functions
///         - SafeERC20 for all token transfers
/// @dev Design patterns used: CEI, ReentrancyGuard, Pull-over-push (caller pulls out)
contract AMM is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Errors ───────────────────────────────────────────────────────────────

    error AMM__ZeroAmount();
    error AMM__ZeroAddress();
    error AMM__InsufficientLiquidity();
    error AMM__SlippageExceeded(uint256 amountOut, uint256 minAmountOut);
    error AMM__InvalidToken(address token);
    error AMM__InsufficientLPShares();
    error AMM__ZeroInitialLiquidity();
    error AMM__Overflow();

    // ─── Events ───────────────────────────────────────────────────────────────

    event Swap(
        address indexed sender, address indexed tokenIn, uint256 amountIn, address indexed tokenOut, uint256 amountOut
    );

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 shares);

    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 shares);

    // ─── Constants ────────────────────────────────────────────────────────────

    uint256 public constant FEE_BPS = 30; // 0.30%
    uint256 public constant FEE_DENOM = 10_000;
    uint256 private constant MINIMUM_LIQUIDITY = 1_000; // burned on first add

    // ─── State ────────────────────────────────────────────────────────────────

    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;

    uint256 public reserveA;
    uint256 public reserveB;

    // LP token accounting (internal ERC20)
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(address _tokenA, address _tokenB) {
        if (_tokenA == address(0) || _tokenB == address(0)) revert AMM__ZeroAddress();
        if (_tokenA == _tokenB) revert AMM__InvalidToken(_tokenB);
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    // ─── LP Token Internal ERC20 ──────────────────────────────────────────────

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function _burn(address from, uint256 amount) internal {
        if (balanceOf[from] < amount) revert AMM__InsufficientLPShares();
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }

    // ─── Core: Add Liquidity ──────────────────────────────────────────────────

    /// @notice Deposit tokenA + tokenB, receive LP shares proportional to contribution.
    ///         First depositor sets the initial price ratio.
    /// @param amountADesired Amount of tokenA to deposit
    /// @param amountBDesired Amount of tokenB to deposit
    /// @return shares LP shares minted to msg.sender
    function addLiquidity(uint256 amountADesired, uint256 amountBDesired)
        external
        nonReentrant
        returns (uint256 shares)
    {
        if (amountADesired == 0 || amountBDesired == 0) revert AMM__ZeroAmount();

        // ── Checks ──────────────────────────────────────────────────────────
        uint256 _totalSupply = totalSupply;
        uint256 _reserveA = reserveA;
        uint256 _reserveB = reserveB;

        // ── Effects ─────────────────────────────────────────────────────────
        if (_totalSupply == 0) {
            // First deposit: geometric mean of amounts, burn MINIMUM_LIQUIDITY
            shares = _sqrt(amountADesired * amountBDesired) - MINIMUM_LIQUIDITY;
            if (shares == 0) revert AMM__ZeroInitialLiquidity();
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock minimum liquidity
        } else {
            // Subsequent deposits: proportional to smaller ratio to preserve price
            uint256 sharesA = (amountADesired * _totalSupply) / _reserveA;
            uint256 sharesB = (amountBDesired * _totalSupply) / _reserveB;
            shares = sharesA < sharesB ? sharesA : sharesB;
            if (shares == 0) revert AMM__InsufficientLiquidity();
        }

        reserveA = _reserveA + amountADesired;
        reserveB = _reserveB + amountBDesired;
        _mint(msg.sender, shares);

        // ── Interactions ────────────────────────────────────────────────────
        tokenA.safeTransferFrom(msg.sender, address(this), amountADesired);
        tokenB.safeTransferFrom(msg.sender, address(this), amountBDesired);

        emit LiquidityAdded(msg.sender, amountADesired, amountBDesired, shares);
    }

    // ─── Core: Remove Liquidity ───────────────────────────────────────────────

    /// @notice Burn LP shares, receive proportional tokenA + tokenB back.
    /// @param shares LP shares to burn
    /// @param minAmountA Minimum tokenA to receive (slippage protection)
    /// @param minAmountB Minimum tokenB to receive (slippage protection)
    /// @return amountA TokenA returned
    /// @return amountB TokenB returned
    function removeLiquidity(uint256 shares, uint256 minAmountA, uint256 minAmountB)
        external
        nonReentrant
        returns (uint256 amountA, uint256 amountB)
    {
        if (shares == 0) revert AMM__ZeroAmount();

        // ── Checks ──────────────────────────────────────────────────────────
        uint256 _totalSupply = totalSupply;
        uint256 _reserveA = reserveA;
        uint256 _reserveB = reserveB;

        amountA = (shares * _reserveA) / _totalSupply;
        amountB = (shares * _reserveB) / _totalSupply;

        if (amountA < minAmountA) revert AMM__SlippageExceeded(amountA, minAmountA);
        if (amountB < minAmountB) revert AMM__SlippageExceeded(amountB, minAmountB);
        if (amountA == 0 || amountB == 0) revert AMM__InsufficientLiquidity();

        // ── Effects ─────────────────────────────────────────────────────────
        _burn(msg.sender, shares);
        reserveA = _reserveA - amountA;
        reserveB = _reserveB - amountB;

        // ── Interactions ────────────────────────────────────────────────────
        tokenA.safeTransfer(msg.sender, amountA);
        tokenB.safeTransfer(msg.sender, amountB);

        emit LiquidityRemoved(msg.sender, amountA, amountB, shares);
    }

    // ─── Core: Swap ───────────────────────────────────────────────────────────

    /// @notice Swap exact tokenIn for tokenOut using constant-product formula with 0.3% fee.
    ///         Fee stays in reserves → k grows after every swap.
    /// @param tokenIn  Address of input token (must be tokenA or tokenB)
    /// @param amountIn Exact amount of tokenIn to sell
    /// @param minAmountOut Minimum amount of tokenOut to receive (slippage guard)
    /// @return amountOut Actual amount of tokenOut sent to msg.sender
    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert AMM__ZeroAmount();
        if (tokenIn != address(tokenA) && tokenIn != address(tokenB)) {
            revert AMM__InvalidToken(tokenIn);
        }

        // ── Checks ──────────────────────────────────────────────────────────
        bool isAtoB = tokenIn == address(tokenA);
        (uint256 reserveIn, uint256 reserveOut) = isAtoB ? (reserveA, reserveB) : (reserveB, reserveA);

        if (reserveIn == 0 || reserveOut == 0) revert AMM__InsufficientLiquidity();

        // Constant-product formula with fee:
        //   amountInWithFee = amountIn * (10000 - 30) = amountIn * 9970
        //   amountOut = reserveOut * amountInWithFee / (reserveIn * 10000 + amountInWithFee)
        uint256 amountInWithFee = amountIn * (FEE_DENOM - FEE_BPS);
        amountOut = (reserveOut * amountInWithFee) / (reserveIn * FEE_DENOM + amountInWithFee);

        if (amountOut < minAmountOut) revert AMM__SlippageExceeded(amountOut, minAmountOut);
        if (amountOut == 0) revert AMM__InsufficientLiquidity();

        // ── Effects ─────────────────────────────────────────────────────────
        if (isAtoB) {
            reserveA = reserveIn + amountIn;
            reserveB = reserveOut - amountOut;
        } else {
            reserveB = reserveIn + amountIn;
            reserveA = reserveOut - amountOut;
        }

        // ── Interactions ────────────────────────────────────────────────────
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(isAtoB ? address(tokenB) : address(tokenA)).safeTransfer(msg.sender, amountOut);

        emit Swap(msg.sender, tokenIn, amountIn, isAtoB ? address(tokenB) : address(tokenA), amountOut);
    }

    // ─── View Helpers ─────────────────────────────────────────────────────────

    /// @notice Quote: how much tokenOut for a given amountIn (no state change)
    function getAmountOut(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        if (tokenIn != address(tokenA) && tokenIn != address(tokenB)) revert AMM__InvalidToken(tokenIn);
        bool isAtoB = tokenIn == address(tokenA);
        (uint256 reserveIn, uint256 reserveOut) = isAtoB ? (reserveA, reserveB) : (reserveB, reserveA);
        if (reserveIn == 0 || reserveOut == 0 || amountIn == 0) return 0;
        uint256 amountInWithFee = amountIn * (FEE_DENOM - FEE_BPS);
        amountOut = (reserveOut * amountInWithFee) / (reserveIn * FEE_DENOM + amountInWithFee);
    }

    /// @notice Returns current k = reserveA * reserveB
    function getK() external view returns (uint256) {
        return reserveA * reserveB;
    }

    /// @notice Returns reserves as a tuple
    function getReserves() external view returns (uint256 _reserveA, uint256 _reserveB) {
        return (reserveA, reserveB);
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
