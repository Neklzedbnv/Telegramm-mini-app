// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "contracts/core/AMM.sol";
import "contracts/mocks/MockERC20.sol";

/// @notice Fuzz tests for AMM — required by BChT2 §3.3
///         "Fuzz tests: at least 10 — including the AMM swap function"
contract AMMFuzzTest is Test {
    AMM internal amm;
    MockERC20 internal tA;
    MockERC20 internal tB;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant SEED_A = 1_000_000e18;
    uint256 internal constant SEED_B = 1_000_000e18;
    uint256 internal constant INITIAL_LIQ_A = 100_000e18;
    uint256 internal constant INITIAL_LIQ_B = 100_000e18;

    function setUp() public {
        tA = new MockERC20("TokenA", "TKA", 18);
        tB = new MockERC20("TokenB", "TKB", 18);
        amm = new AMM(address(tA), address(tB));

        // Seed alice with tokens
        tA.mint(alice, SEED_A);
        tB.mint(alice, SEED_B);
        tA.mint(bob, SEED_A);
        tB.mint(bob, SEED_B);

        // Alice seeds the pool
        vm.startPrank(alice);
        tA.approve(address(amm), INITIAL_LIQ_A);
        tB.approve(address(amm), INITIAL_LIQ_B);
        amm.addLiquidity(INITIAL_LIQ_A, INITIAL_LIQ_B);
        vm.stopPrank();
    }

    // ─── Swap Fuzz Tests ──────────────────────────────────────────────────────

    /// @notice Any valid amountIn for tokenA → positive amountOut of tokenB
    function testFuzz_swap_tokenAtoB_amountOut_positive(uint256 amountIn) public {
        amountIn = bound(amountIn, 1e15, 10_000e18); // 0.001 → 10k tokens
        tA.mint(bob, amountIn);

        vm.startPrank(bob);
        tA.approve(address(amm), amountIn);
        uint256 amountOut = amm.swap(address(tA), amountIn, 0);
        vm.stopPrank();

        assertGt(amountOut, 0, "amountOut must be positive");
    }

    /// @notice Any valid amountIn for tokenB → positive amountOut of tokenA
    function testFuzz_swap_tokenBtoA_amountOut_positive(uint256 amountIn) public {
        amountIn = bound(amountIn, 1e15, 10_000e18);
        tB.mint(bob, amountIn);

        vm.startPrank(bob);
        tB.approve(address(amm), amountIn);
        uint256 amountOut = amm.swap(address(tB), amountIn, 0);
        vm.stopPrank();

        assertGt(amountOut, 0, "amountOut must be positive");
    }

    /// @notice Slippage protection: reverts when actual amountOut < minAmountOut
    function testFuzz_swap_slippageProtection_reverts(uint256 amountIn) public {
        amountIn = bound(amountIn, 1e15, 10_000e18);
        tA.mint(bob, amountIn);

        uint256 quoted = amm.getAmountOut(address(tA), amountIn);
        uint256 tooHighMin = quoted + 1;

        vm.startPrank(bob);
        tA.approve(address(amm), amountIn);
        vm.expectRevert(abi.encodeWithSelector(AMM.AMM__SlippageExceeded.selector, quoted, tooHighMin));
        amm.swap(address(tA), amountIn, tooHighMin);
        vm.stopPrank();
    }

    /// @notice Fee always charged: amountOut < ideal constant-product output (no fee)
    function testFuzz_swap_feeAlwaysCharged(uint256 amountIn) public {
        amountIn = bound(amountIn, 1e15, 10_000e18);

        (uint256 rA, uint256 rB) = amm.getReserves();
        // Ideal output without fee: reserveB * amountIn / (reserveA + amountIn)
        uint256 idealOut = (rB * amountIn) / (rA + amountIn);
        uint256 actualOut = amm.getAmountOut(address(tA), amountIn);

        assertLt(actualOut, idealOut, "fee must reduce output vs ideal");
    }

    /// @notice After any swap, both reserves remain > 0
    function testFuzz_swap_reservesNeverZero(uint256 amountIn) public {
        amountIn = bound(amountIn, 1e15, 50_000e18);
        tA.mint(bob, amountIn);

        vm.startPrank(bob);
        tA.approve(address(amm), amountIn);
        amm.swap(address(tA), amountIn, 0);
        vm.stopPrank();

        (uint256 rA, uint256 rB) = amm.getReserves();
        assertGt(rA, 0);
        assertGt(rB, 0);
    }

    /// @notice k must not decrease after a swap (fee keeps it non-decreasing)
    function testFuzz_swap_kNeverDecreases(uint256 amountIn) public {
        amountIn = bound(amountIn, 1e15, 10_000e18);
        uint256 kBefore = amm.getK();

        tA.mint(bob, amountIn);
        vm.startPrank(bob);
        tA.approve(address(amm), amountIn);
        amm.swap(address(tA), amountIn, 0);
        vm.stopPrank();

        uint256 kAfter = amm.getK();
        assertGe(kAfter, kBefore, "k must never decrease on swap");
    }

    // ─── Liquidity Fuzz Tests ─────────────────────────────────────────────────

    /// @notice Any valid amounts → LP shares > 0
    function testFuzz_addLiquidity_receivesShares(uint256 amtA, uint256 amtB) public {
        amtA = bound(amtA, 1e15, 100_000e18);
        amtB = bound(amtB, 1e15, 100_000e18);
        tA.mint(bob, amtA);
        tB.mint(bob, amtB);

        vm.startPrank(bob);
        tA.approve(address(amm), amtA);
        tB.approve(address(amm), amtB);
        uint256 shares = amm.addLiquidity(amtA, amtB);
        vm.stopPrank();

        assertGt(shares, 0, "shares must be positive");
    }

    /// @notice Round-trip add→remove: user receives back tokens (≤ deposited due to rounding)
    function testFuzz_removeLiquidity_returnsAssets(uint256 amtA, uint256 amtB) public {
        amtA = bound(amtA, 1e15, 100_000e18);
        amtB = bound(amtB, 1e15, 100_000e18);
        tA.mint(bob, amtA);
        tB.mint(bob, amtB);

        vm.startPrank(bob);
        tA.approve(address(amm), amtA);
        tB.approve(address(amm), amtB);
        uint256 shares = amm.addLiquidity(amtA, amtB);

        uint256 balABefore = tA.balanceOf(bob);
        uint256 balBBefore = tB.balanceOf(bob);
        (uint256 outA, uint256 outB) = amm.removeLiquidity(shares, 0, 0);
        vm.stopPrank();

        assertGt(outA, 0);
        assertGt(outB, 0);
        assertGe(tA.balanceOf(bob), balABefore);
        assertGe(tB.balanceOf(bob), balBBefore);
    }

    /// @notice Multiple sequential swaps: k only increases
    function testFuzz_multipleSwaps_kOnlyIncreases(uint256 amountIn1, uint256 amountIn2) public {
        amountIn1 = bound(amountIn1, 1e15, 5_000e18);
        amountIn2 = bound(amountIn2, 1e15, 5_000e18);
        uint256 kInitial = amm.getK();

        tA.mint(bob, amountIn1 + amountIn2);
        vm.startPrank(bob);
        tA.approve(address(amm), amountIn1 + amountIn2);
        amm.swap(address(tA), amountIn1, 0);
        uint256 kMid = amm.getK();
        amm.swap(address(tA), amountIn2, 0);
        uint256 kFinal = amm.getK();
        vm.stopPrank();

        assertGe(kMid, kInitial, "k must not decrease after first swap");
        assertGe(kFinal, kMid, "k must not decrease after second swap");
    }
}
