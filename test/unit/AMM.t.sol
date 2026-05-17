// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "contracts/core/AMM.sol";
import "contracts/mocks/MockERC20.sol";

contract AMMUnitTest is Test {
    AMM internal amm;
    MockERC20 internal tA;
    MockERC20 internal tB;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 constant SEED_A = 100_000e18;
    uint256 constant SEED_B = 100_000e18;

    function setUp() public {
        tA = new MockERC20("TokenA", "TKA", 18);
        tB = new MockERC20("TokenB", "TKB", 18);
        amm = new AMM(address(tA), address(tB));

        tA.mint(alice, SEED_A);
        tB.mint(alice, SEED_B);
        vm.startPrank(alice);
        tA.approve(address(amm), SEED_A);
        tB.approve(address(amm), SEED_B);
        amm.addLiquidity(SEED_A, SEED_B);
        vm.stopPrank();
    }

    // ─── Constructor ──────────────────────────────────────────────────────────

    function test_constructor_setsTokens() public view {
        assertEq(address(amm.tokenA()), address(tA));
        assertEq(address(amm.tokenB()), address(tB));
    }

    function test_constructor_revertsZeroAddress() public {
        vm.expectRevert(AMM.AMM__ZeroAddress.selector);
        new AMM(address(0), address(tA));
    }

    function test_constructor_revertsSameToken() public {
        vm.expectRevert(abi.encodeWithSelector(AMM.AMM__InvalidToken.selector, address(tA)));
        new AMM(address(tA), address(tA));
    }

    // ─── addLiquidity ─────────────────────────────────────────────────────────

    function test_addLiquidity_firstDeposit_mintsShares() public view {
        uint256 shares = amm.balanceOf(alice);
        assertGt(shares, 0, "alice should have LP shares");
    }

    function test_addLiquidity_setsReserves() public view {
        assertEq(amm.reserveA(), SEED_A);
        assertEq(amm.reserveB(), SEED_B);
    }

    function test_addLiquidity_subsequentDeposit() public {
        uint256 amt = 10_000e18;
        tA.mint(bob, amt);
        tB.mint(bob, amt);
        vm.startPrank(bob);
        tA.approve(address(amm), amt);
        tB.approve(address(amm), amt);
        uint256 shares = amm.addLiquidity(amt, amt);
        vm.stopPrank();
        assertGt(shares, 0);
        assertGt(amm.balanceOf(bob), 0);
    }

    function test_addLiquidity_revertsZeroAmount() public {
        vm.expectRevert(AMM.AMM__ZeroAmount.selector);
        amm.addLiquidity(0, 1e18);
    }

    function test_addLiquidity_emitsEvent() public {
        uint256 amt = 1_000e18;
        tA.mint(bob, amt);
        tB.mint(bob, amt);
        vm.startPrank(bob);
        tA.approve(address(amm), amt);
        tB.approve(address(amm), amt);
        vm.expectEmit(true, false, false, false);
        emit AMM.LiquidityAdded(bob, amt, amt, 0);
        amm.addLiquidity(amt, amt);
        vm.stopPrank();
    }

    // ─── removeLiquidity ──────────────────────────────────────────────────────

    function test_removeLiquidity_returnsTokens() public {
        uint256 shares = amm.balanceOf(alice);
        uint256 half = shares / 2;
        uint256 balABefore = tA.balanceOf(alice);
        uint256 balBBefore = tB.balanceOf(alice);

        vm.prank(alice);
        (uint256 amtA, uint256 amtB) = amm.removeLiquidity(half, 0, 0);

        assertGt(amtA, 0);
        assertGt(amtB, 0);
        assertEq(tA.balanceOf(alice), balABefore + amtA);
        assertEq(tB.balanceOf(alice), balBBefore + amtB);
    }

    function test_removeLiquidity_revertsZeroShares() public {
        vm.expectRevert(AMM.AMM__ZeroAmount.selector);
        vm.prank(alice);
        amm.removeLiquidity(0, 0, 0);
    }

    function test_removeLiquidity_revertsSlippage() public {
        uint256 shares = amm.balanceOf(alice) / 10;
        vm.prank(alice);
        vm.expectRevert();
        amm.removeLiquidity(shares, type(uint256).max, 0);
    }

    function test_removeLiquidity_revertsInsufficientShares() public {
        vm.prank(bob);
        vm.expectRevert();
        amm.removeLiquidity(1e18, 0, 0);
    }

    function test_removeLiquidity_emitsEvent() public {
        uint256 shares = amm.balanceOf(alice) / 4;
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit AMM.LiquidityRemoved(alice, 0, 0, shares);
        amm.removeLiquidity(shares, 0, 0);
    }

    // ─── swap ─────────────────────────────────────────────────────────────────

    function test_swap_aToB_sendsTokenB() public {
        uint256 amtIn = 1_000e18;
        tA.mint(bob, amtIn);
        uint256 balBBefore = tB.balanceOf(bob);

        vm.startPrank(bob);
        tA.approve(address(amm), amtIn);
        uint256 out = amm.swap(address(tA), amtIn, 0);
        vm.stopPrank();

        assertGt(out, 0);
        assertEq(tB.balanceOf(bob), balBBefore + out);
    }

    function test_swap_bToA_sendsTokenA() public {
        uint256 amtIn = 1_000e18;
        tB.mint(bob, amtIn);
        uint256 balABefore = tA.balanceOf(bob);

        vm.startPrank(bob);
        tB.approve(address(amm), amtIn);
        uint256 out = amm.swap(address(tB), amtIn, 0);
        vm.stopPrank();

        assertGt(out, 0);
        assertEq(tA.balanceOf(bob), balABefore + out);
    }

    function test_swap_revertsZeroAmount() public {
        vm.expectRevert(AMM.AMM__ZeroAmount.selector);
        vm.prank(bob);
        amm.swap(address(tA), 0, 0);
    }

    function test_swap_revertsInvalidToken() public {
        address rando = makeAddr("rando");
        vm.expectRevert(abi.encodeWithSelector(AMM.AMM__InvalidToken.selector, rando));
        vm.prank(bob);
        amm.swap(rando, 1e18, 0);
    }

    function test_swap_revertsSlippage() public {
        uint256 amtIn = 1_000e18;
        tA.mint(bob, amtIn);
        vm.startPrank(bob);
        tA.approve(address(amm), amtIn);
        vm.expectRevert();
        amm.swap(address(tA), amtIn, type(uint256).max);
        vm.stopPrank();
    }

    function test_swap_kNeverDecreases() public {
        uint256 kBefore = amm.getK();
        uint256 amtIn = 5_000e18;
        tA.mint(bob, amtIn);
        vm.startPrank(bob);
        tA.approve(address(amm), amtIn);
        amm.swap(address(tA), amtIn, 0);
        vm.stopPrank();
        assertGe(amm.getK(), kBefore);
    }

    function test_swap_emitsEvent() public {
        uint256 amtIn = 500e18;
        tA.mint(bob, amtIn);
        vm.startPrank(bob);
        tA.approve(address(amm), amtIn);
        vm.expectEmit(true, true, false, false);
        emit AMM.Swap(bob, address(tA), amtIn, address(tB), 0);
        amm.swap(address(tA), amtIn, 0);
        vm.stopPrank();
    }

    // ─── View helpers ─────────────────────────────────────────────────────────

    function test_getAmountOut_correctValue() public view {
        uint256 amtIn = 1_000e18;
        uint256 quote = amm.getAmountOut(address(tA), amtIn);
        assertGt(quote, 0);
        // with 0.3% fee, output < input (symmetric pool)
        assertLt(quote, amtIn);
    }

    function test_getAmountOut_zeroInput_returnsZero() public view {
        assertEq(amm.getAmountOut(address(tA), 0), 0);
    }

    function test_getAmountOut_invalidToken_reverts() public {
        vm.expectRevert();
        amm.getAmountOut(makeAddr("bad"), 1e18);
    }

    function test_getK_isProductOfReserves() public view {
        (uint256 rA, uint256 rB) = amm.getReserves();
        assertEq(amm.getK(), rA * rB);
    }

    function test_reservesMatchBalances() public view {
        assertEq(amm.reserveA(), tA.balanceOf(address(amm)));
        assertEq(amm.reserveB(), tB.balanceOf(address(amm)));
    }

    function test_totalSupply_positive() public view {
        assertGt(amm.totalSupply(), 0);
    }
}
