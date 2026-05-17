// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../contracts/core/LendingPoolV1.sol";
import "../../contracts/core/LendingPoolV2.sol";
import "../../contracts/mocks/MockERC20.sol";
import "../../contracts/mocks/MockOracle.sol";

contract LendingPoolCoreTest is Test {
    LendingPoolV1 pool;
    MockOracle oracle;
    MockERC20 usdc;
    MockERC20 weth;

    address owner = address(this);
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address liquidator = makeAddr("liquidator");

    uint256 constant USDC_PRICE = 1e30;
    uint256 constant WETH_PRICE = 2000e18;
    uint256 constant PRECISION = 1e18;

    function setUp() public {
        vm.warp(100_000);

        oracle = new MockOracle();
        LendingPoolV1 impl = new LendingPoolV1();
        bytes memory initData = abi.encodeCall(LendingPoolV1.initialize, (address(oracle), owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        pool = LendingPoolV1(address(proxy));

        usdc = new MockERC20("USDC", "USDC", 6);
        weth = new MockERC20("WETH", "WETH", 18);

        oracle.setPrice(address(usdc), USDC_PRICE);
        oracle.setPrice(address(weth), WETH_PRICE);

        pool.addSupportedToken(address(usdc));
        pool.addSupportedToken(address(weth));

        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);
        usdc.mint(charlie, 100_000e6);
        usdc.mint(liquidator, 100_000e6);
        weth.mint(alice, 100e18);
        weth.mint(bob, 100e18);
        weth.mint(liquidator, 100e18);

        vm.prank(alice);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(alice);
        weth.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        weth.approve(address(pool), type(uint256).max);
        vm.prank(charlie);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(liquidator);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(liquidator);
        weth.approve(address(pool), type(uint256).max);
    }

    // ─── Deposit ──────────────────────────────────────────────────────────────

    function test_deposit_succeeds() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);
        assertEq(pool.getCollateral(alice, address(usdc)), 1000e6);
    }

    function test_deposit_updatesTotal() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);
        assertEq(pool.totalDeposits(address(usdc)), 1000e6);
    }

    function test_deposit_emitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ILendingPool.Deposited(alice, address(usdc), 1000e6);
        pool.deposit(address(usdc), 1000e6);
    }

    function test_deposit_revertsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(LendingPoolV1.ZeroAmount.selector);
        pool.deposit(address(usdc), 0);
    }

    function test_deposit_revertsUnsupportedToken() public {
        address fake = makeAddr("fake");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LendingPoolV1.TokenNotSupported.selector, fake));
        pool.deposit(fake, 100);
    }

    function test_deposit_multipleDeposits() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 500e6);
        vm.prank(alice);
        pool.deposit(address(usdc), 500e6);
        assertEq(pool.getCollateral(alice, address(usdc)), 1000e6);
    }

    function test_deposit_multipleUsers_totalAccumulates() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);
        vm.prank(bob);
        pool.deposit(address(usdc), 2000e6);
        assertEq(pool.totalDeposits(address(usdc)), 3000e6);
    }

    function test_deposit_weth_succeeds() public {
        vm.prank(alice);
        pool.deposit(address(weth), 1e18);
        assertEq(pool.getCollateral(alice, address(weth)), 1e18);
    }

    // ─── Borrow ───────────────────────────────────────────────────────────────

    function test_borrow_succeeds() public {
        _depositLiquidity(bob, 5000e6);
        vm.prank(alice);
        pool.deposit(address(usdc), 2000e6);
        vm.prank(alice);
        pool.borrow(address(usdc), 1000e6);
        assertEq(pool.getDebt(alice, address(usdc)), 1000e6);
    }

    function test_borrow_transfersTokensToUser() public {
        _depositLiquidity(bob, 5000e6);
        vm.prank(alice);
        pool.deposit(address(usdc), 2000e6);
        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        pool.borrow(address(usdc), 1000e6);
        assertEq(usdc.balanceOf(alice), balBefore + 1000e6);
    }

    function test_borrow_updatesTotalBorrows() public {
        _depositLiquidity(bob, 5000e6);
        vm.prank(alice);
        pool.deposit(address(usdc), 2000e6);
        vm.prank(alice);
        pool.borrow(address(usdc), 1000e6);
        assertEq(pool.totalBorrows(address(usdc)), 1000e6);
    }

    function test_borrow_emitsEvent() public {
        _depositLiquidity(bob, 5000e6);
        vm.prank(alice);
        pool.deposit(address(usdc), 2000e6);
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ILendingPool.Borrowed(alice, address(usdc), 1000e6);
        pool.borrow(address(usdc), 1000e6);
    }

    function test_borrow_revertsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(LendingPoolV1.ZeroAmount.selector);
        pool.borrow(address(usdc), 0);
    }

    function test_borrow_revertsInsufficientLiquidity() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 500e6);
        vm.prank(alice);
        vm.expectRevert();
        pool.borrow(address(usdc), 600e6);
    }

    function test_borrow_revertsIfExceedsLTV() public {
        _depositLiquidity(bob, 5000e6);
        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);
        vm.prank(alice);
        vm.expectRevert();
        pool.borrow(address(usdc), 900e6); // 90% > 75% LTV
    }

    function test_borrow_crossCollateral_wethForUsdc() public {
        _depositLiquidity(bob, 5000e6);
        vm.prank(alice);
        pool.deposit(address(weth), 1e18); // 1 WETH = $2000
        vm.prank(alice);
        pool.borrow(address(usdc), 1000e6); // borrow $1000 against $2000 WETH
        assertEq(pool.getDebt(alice, address(usdc)), 1000e6);
    }

    function test_borrow_revertsUnsupportedToken() public {
        address fake = makeAddr("fake");
        vm.prank(alice);
        vm.expectRevert();
        pool.borrow(fake, 100);
    }

    // ─── Repay ────────────────────────────────────────────────────────────────

    function test_repay_succeeds() public {
        _borrow(alice, bob, 2000e6, 500e6);
        vm.prank(alice);
        pool.repay(address(usdc), 500e6);
        assertEq(pool.getDebt(alice, address(usdc)), 0);
    }

    function test_repay_partialRepay() public {
        _borrow(alice, bob, 2000e6, 500e6);
        vm.prank(alice);
        pool.repay(address(usdc), 200e6);
        assertEq(pool.getDebt(alice, address(usdc)), 300e6);
    }

    function test_repay_capsAtDebt() public {
        _borrow(alice, bob, 2000e6, 500e6);
        vm.prank(alice);
        pool.repay(address(usdc), 1000e6); // over-repay
        assertEq(pool.getDebt(alice, address(usdc)), 0);
    }

    function test_repay_revertsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(LendingPoolV1.ZeroAmount.selector);
        pool.repay(address(usdc), 0);
    }

    function test_repay_updatesTotalBorrows() public {
        _borrow(alice, bob, 2000e6, 500e6);
        uint256 before = pool.totalBorrows(address(usdc));
        vm.prank(alice);
        pool.repay(address(usdc), 200e6);
        assertEq(pool.totalBorrows(address(usdc)), before - 200e6);
    }

    function test_repay_emitsEvent() public {
        _borrow(alice, bob, 2000e6, 500e6);
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ILendingPool.Repaid(alice, address(usdc), 200e6);
        pool.repay(address(usdc), 200e6);
    }

    // ─── Withdraw ─────────────────────────────────────────────────────────────

    function test_withdraw_succeeds() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);
        vm.prank(alice);
        pool.withdraw(address(usdc), 500e6);
        assertEq(pool.getCollateral(alice, address(usdc)), 500e6);
    }

    function test_withdraw_fullAmount_noDebt() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);
        vm.prank(alice);
        pool.withdraw(address(usdc), 1000e6);
        assertEq(pool.getCollateral(alice, address(usdc)), 0);
    }

    function test_withdraw_emitsEvent() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ILendingPool.Withdrawn(alice, address(usdc), 500e6);
        pool.withdraw(address(usdc), 500e6);
    }

    function test_withdraw_revertsInsufficientCollateral() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 500e6);
        vm.prank(alice);
        vm.expectRevert();
        pool.withdraw(address(usdc), 1000e6);
    }

    function test_withdraw_revertsIfBreaksHealthFactor() public {
        _borrow(alice, bob, 2000e6, 1000e6);
        vm.prank(alice);
        vm.expectRevert();
        pool.withdraw(address(usdc), 1800e6); // would drop HF below 1
    }

    function test_withdraw_allowedAfterRepay() public {
        _borrow(alice, bob, 2000e6, 1000e6);
        vm.prank(alice);
        pool.repay(address(usdc), 1000e6);
        vm.prank(alice);
        pool.withdraw(address(usdc), 2000e6);
        assertEq(pool.getCollateral(alice, address(usdc)), 0);
    }

    function test_withdraw_updatesTotalDeposits() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);
        vm.prank(alice);
        pool.withdraw(address(usdc), 300e6);
        assertEq(pool.totalDeposits(address(usdc)), 700e6);
    }

    // ─── Health Factor ────────────────────────────────────────────────────────

    function test_healthFactor_noDebt_returnsMax() public view {
        assertEq(pool.healthFactor(alice), type(uint256).max);
    }

    function test_healthFactor_noCollateral_returnsMax() public view {
        assertEq(pool.healthFactor(charlie), type(uint256).max);
    }

    function test_healthFactor_afterBorrow_greaterThanOne() public {
        _borrow(alice, bob, 2000e6, 1000e6);
        assertGt(pool.healthFactor(alice), PRECISION);
    }

    function test_healthFactor_at75LTV_isSafe() public {
        _depositLiquidity(bob, 10000e6);
        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);
        vm.prank(alice);
        pool.borrow(address(usdc), 750e6); // exactly 75% LTV
        assertGt(pool.healthFactor(alice), PRECISION);
    }

    function test_healthFactor_belowOne_afterPriceDrop() public {
        _depositLiquidity(bob, 5000e6);
        vm.prank(alice);
        pool.deposit(address(weth), 1e18); // $2000 WETH
        vm.prank(alice);
        pool.borrow(address(usdc), 1400e6); // $1400 borrowed
        // Drop WETH price: 1400 * 100/80 = 1750, so price below 1750 → HF < 1
        oracle.setPrice(address(weth), 1500e18);
        assertLt(pool.healthFactor(alice), PRECISION);
    }

    // ─── Liquidation ──────────────────────────────────────────────────────────

    function test_liquidate_succeeds() public {
        _setupLiquidatable();
        uint256 debt = pool.getDebt(alice, address(usdc));
        vm.prank(liquidator);
        pool.liquidate(alice, address(weth), address(usdc), debt);
        assertLt(pool.getDebt(alice, address(usdc)), debt);
    }

    function test_liquidate_emitsEvent() public {
        _setupLiquidatable();
        uint256 debt = pool.getDebt(alice, address(usdc));
        vm.prank(liquidator);
        vm.expectEmit(true, true, true, false);
        emit ILendingPool.Liquidated(liquidator, alice, address(weth), address(usdc), 0, 0);
        pool.liquidate(alice, address(weth), address(usdc), debt);
    }

    function test_liquidate_revertsIfHealthFactorOk() public {
        _depositLiquidity(bob, 5000e6);
        vm.prank(alice);
        pool.deposit(address(usdc), 2000e6);
        vm.prank(alice);
        pool.borrow(address(usdc), 500e6); // safe position
        vm.prank(liquidator);
        vm.expectRevert();
        pool.liquidate(alice, address(usdc), address(usdc), 100e6);
    }

    function test_liquidate_revertsZeroAmount() public {
        vm.prank(liquidator);
        vm.expectRevert(LendingPoolV1.ZeroAmount.selector);
        pool.liquidate(alice, address(usdc), address(usdc), 0);
    }

    function test_liquidate_liquidatorReceivesCollateral() public {
        _setupLiquidatable();
        uint256 wethBefore = weth.balanceOf(liquidator);
        uint256 debt = pool.getDebt(alice, address(usdc));
        vm.prank(liquidator);
        pool.liquidate(alice, address(weth), address(usdc), debt);
        assertGt(weth.balanceOf(liquidator), wethBefore);
    }

    // ─── getTokenList ─────────────────────────────────────────────────────────

    function test_getTokenList_returnsAll() public view {
        address[] memory list = pool.getTokenList();
        assertEq(list.length, 2);
        assertEq(list[0], address(usdc));
        assertEq(list[1], address(weth));
    }

    function test_getTokenList_emptyInitially() public {
        LendingPoolV1 impl2 = new LendingPoolV1();
        bytes memory init = abi.encodeCall(LendingPoolV1.initialize, (address(oracle), owner));
        LendingPoolV1 pool2 = LendingPoolV1(address(new ERC1967Proxy(address(impl2), init)));
        assertEq(pool2.getTokenList().length, 0);
    }

    // ─── Constants ────────────────────────────────────────────────────────────

    function test_constants_correct() public view {
        assertEq(pool.LTV_RATIO(), 75);
        assertEq(pool.LIQUIDATION_THRESHOLD(), 80);
        assertEq(pool.LIQUIDATION_BONUS(), 5);
        assertEq(pool.MIN_HEALTH_FACTOR(), 1e18);
        assertEq(pool.STALE_PRICE_DELAY(), 1 hours);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    function _depositLiquidity(address user, uint256 amount) internal {
        vm.prank(user);
        pool.deposit(address(usdc), amount);
    }

    function _borrow(address borrower, address provider, uint256 deposit, uint256 borrow) internal {
        vm.prank(provider);
        pool.deposit(address(usdc), deposit * 2);
        vm.prank(borrower);
        pool.deposit(address(usdc), deposit);
        vm.prank(borrower);
        pool.borrow(address(usdc), borrow);
    }

    function _setupLiquidatable() internal {
        _depositLiquidity(bob, 10_000e6);
        vm.prank(alice);
        pool.deposit(address(weth), 1e18); // $2000 WETH
        vm.prank(alice);
        pool.borrow(address(usdc), 1400e6); // 70% LTV
        // Drop WETH to $1500 → HF = 1500*0.8/1400 < 1
        oracle.setPrice(address(weth), 1500e18);
    }
}
