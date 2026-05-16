// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/LendingPool.sol";
import "../../src/LendingPoolV2.sol";
import "../../src/mocks/MockERC20.sol";
import "../../src/mocks/MockOracle.sol";

contract LendingPoolTest is Test {
    LendingPool pool;
    MockOracle oracle;
    MockERC20 usdc;
    MockERC20 weth;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address liquidator = makeAddr("liquidator");

    // Prices are "USD value per smallest token unit * 1e18"
    // USDC (6 decimals): $1 per token → $1 per 1e6 units → 1e18 / 1e6 * 1e18 = 1e30
    uint256 constant USDC_PRICE = 1e30;
    // WETH (18 decimals): $2000 per token → $2000 per 1e18 units → 2000e18 / 1e18 * 1e18 = 2000e18
    uint256 constant WETH_PRICE = 2000e18;
    uint256 constant PRECISION = 1e18;

    function setUp() public {
        oracle = new MockOracle();
        oracle.setPrice(address(0), 0); // default zero

        LendingPool impl = new LendingPool();
        bytes memory initData = abi.encodeCall(LendingPool.initialize, (address(oracle), address(this)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        pool = LendingPool(address(proxy));

        usdc = new MockERC20("USDC", "USDC", 6);
        weth = new MockERC20("WETH", "WETH", 18);

        oracle.setPrice(address(usdc), USDC_PRICE);
        oracle.setPrice(address(weth), WETH_PRICE);

        pool.addSupportedToken(address(usdc));
        pool.addSupportedToken(address(weth));

        // Fund users
        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);
        usdc.mint(liquidator, 100_000e6);
        weth.mint(alice, 100e18);
        weth.mint(bob, 100e18);

        vm.prank(alice);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(alice);
        weth.approve(address(pool), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        weth.approve(address(pool), type(uint256).max);

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
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.deposit(address(usdc), 0);
    }

    function test_deposit_revertsUnsupportedToken() public {
        address fakeToken = makeAddr("fake");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LendingPool.TokenNotSupported.selector, fakeToken));
        pool.deposit(fakeToken, 100);
    }

    function test_deposit_multipleDeposits() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 500e6);
        vm.prank(alice);
        pool.deposit(address(usdc), 500e6);
        assertEq(pool.getCollateral(alice, address(usdc)), 1000e6);
    }

    // ─── Borrow ───────────────────────────────────────────────────────────────

    function test_borrow_succeeds() public {
        _depositAndBorrow(alice, 2000e6, address(usdc), 1000e6);
        assertEq(pool.getDebt(alice, address(usdc)), 1000e6);
    }

    function test_borrow_transfersTokens() public {
        uint256 balBefore = usdc.balanceOf(alice);
        _depositAndBorrow(alice, 2000e6, address(usdc), 1000e6);
        assertEq(usdc.balanceOf(alice), balBefore - 2000e6 + 1000e6);
    }

    function test_borrow_revertsZeroAmount() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);
        vm.prank(alice);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.borrow(address(usdc), 0);
    }

    function test_borrow_revertsInsufficientLiquidity() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 500e6);
        vm.prank(alice);
        vm.expectRevert(); // InsufficientLiquidity
        pool.borrow(address(usdc), 1000e6);
    }

    function test_borrow_revertsIfHealthFactorBreached() public {
        // Deposit 1000 USDC, try to borrow 900 USDC (90% LTV — above 75% limit)
        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);
        vm.prank(bob);
        pool.deposit(address(usdc), 500e6); // provide liquidity

        vm.prank(alice);
        vm.expectRevert(); // HealthFactorTooLow
        pool.borrow(address(usdc), 900e6);
    }

    function test_borrow_crossCollateral() public {
        // Alice deposits WETH, borrows USDC
        vm.prank(bob);
        pool.deposit(address(usdc), 5000e6); // provide USDC liquidity

        vm.prank(alice);
        pool.deposit(address(weth), 1e18); // 1 WETH = $2000

        vm.prank(alice);
        pool.borrow(address(usdc), 1000e6); // borrow $1000 of USDC
        assertEq(pool.getDebt(alice, address(usdc)), 1000e6);
    }

    function test_borrow_emitsEvent() public {
        vm.prank(bob);
        pool.deposit(address(usdc), 5000e6);
        vm.prank(alice);
        pool.deposit(address(usdc), 2000e6);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ILendingPool.Borrowed(alice, address(usdc), 1000e6);
        pool.borrow(address(usdc), 1000e6);
    }

    // ─── Repay ────────────────────────────────────────────────────────────────

    function test_repay_succeeds() public {
        _depositAndBorrow(alice, 2000e6, address(usdc), 500e6);
        vm.prank(alice);
        pool.repay(address(usdc), 500e6);
        assertEq(pool.getDebt(alice, address(usdc)), 0);
    }

    function test_repay_partialRepay() public {
        _depositAndBorrow(alice, 2000e6, address(usdc), 500e6);
        vm.prank(alice);
        pool.repay(address(usdc), 200e6);
        assertEq(pool.getDebt(alice, address(usdc)), 300e6);
    }

    function test_repay_capsAtDebt() public {
        _depositAndBorrow(alice, 2000e6, address(usdc), 500e6);
        vm.prank(alice);
        pool.repay(address(usdc), 1000e6); // repay more than debt
        assertEq(pool.getDebt(alice, address(usdc)), 0);
    }

    function test_repay_revertsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.repay(address(usdc), 0);
    }

    function test_repay_updatesTotalBorrows() public {
        _depositAndBorrow(alice, 2000e6, address(usdc), 500e6);
        uint256 before = pool.totalBorrows(address(usdc));
        vm.prank(alice);
        pool.repay(address(usdc), 200e6);
        assertEq(pool.totalBorrows(address(usdc)), before - 200e6);
    }

    // ─── Withdraw ─────────────────────────────────────────────────────────────

    function test_withdraw_succeeds() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);
        vm.prank(alice);
        pool.withdraw(address(usdc), 500e6);
        assertEq(pool.getCollateral(alice, address(usdc)), 500e6);
    }

    function test_withdraw_fullAmount() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);
        vm.prank(alice);
        pool.withdraw(address(usdc), 1000e6);
        assertEq(pool.getCollateral(alice, address(usdc)), 0);
    }

    function test_withdraw_revertsIfHealthFactorBreached() public {
        _depositAndBorrow(alice, 2000e6, address(usdc), 1000e6);
        vm.prank(alice);
        vm.expectRevert(); // HealthFactorTooLow
        pool.withdraw(address(usdc), 1500e6);
    }

    function test_withdraw_revertsInsufficientCollateral() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 500e6);
        vm.prank(alice);
        vm.expectRevert(); // InsufficientCollateral
        pool.withdraw(address(usdc), 1000e6);
    }

    function test_withdraw_emitsEvent() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ILendingPool.Withdrawn(alice, address(usdc), 500e6);
        pool.withdraw(address(usdc), 500e6);
    }

    // ─── Health Factor ────────────────────────────────────────────────────────

    function test_healthFactor_noDebt_returnsMax() public view {
        assertEq(pool.healthFactor(alice), type(uint256).max);
    }

    function test_healthFactor_afterBorrow() public {
        _depositAndBorrow(alice, 2000e6, address(usdc), 1000e6);
        uint256 hf = pool.healthFactor(alice);
        // collateral $2000 * 80% / debt $1000 = 1.6
        assertGt(hf, PRECISION);
    }

    function test_healthFactor_atLiquidationThreshold() public {
        vm.prank(bob);
        pool.deposit(address(usdc), 10000e6);

        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);
        vm.prank(alice);
        pool.borrow(address(usdc), 750e6); // exactly 75% LTV

        uint256 hf = pool.healthFactor(alice);
        // 1000 * 80% / 750 ≈ 1.066 > 1
        assertGt(hf, PRECISION);
    }

    // ─── Liquidation ──────────────────────────────────────────────────────────

    function test_liquidate_succeeds() public {
        _setupLiquidatablePosition();

        uint256 debtBefore = pool.getDebt(alice, address(usdc));
        vm.prank(liquidator);
        pool.liquidate(alice, address(weth), address(usdc), debtBefore);

        assertLt(pool.getDebt(alice, address(usdc)), debtBefore);
    }

    function test_liquidate_revertsIfHealthFactorOk() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 2000e6);

        vm.prank(bob);
        pool.deposit(address(usdc), 5000e6);

        vm.prank(alice);
        pool.borrow(address(usdc), 500e6);

        vm.prank(liquidator);
        vm.expectRevert(); // HealthFactorOk
        pool.liquidate(alice, address(usdc), address(usdc), 100e6);
    }

    function test_liquidate_revertsZeroAmount() public {
        vm.prank(liquidator);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.liquidate(alice, address(usdc), address(usdc), 0);
    }

    function test_liquidate_emitsEvent() public {
        _setupLiquidatablePosition();
        uint256 debt = pool.getDebt(alice, address(usdc));

        vm.prank(liquidator);
        vm.expectEmit(true, true, true, false);
        emit ILendingPool.Liquidated(liquidator, alice, address(weth), address(usdc), 0, 0);
        pool.liquidate(alice, address(weth), address(usdc), debt);
    }

    // ─── UUPS Upgrade ─────────────────────────────────────────────────────────

    function test_upgrade_toV2() public {
        assertEq(pool.version(), "1.0.0");

        LendingPoolV2 implV2 = new LendingPoolV2();
        pool.upgradeToAndCall(address(implV2), "");

        LendingPoolV2 poolV2 = LendingPoolV2(address(pool));
        assertEq(poolV2.version(), "2.0.0");
    }

    function test_upgrade_preservesState() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 1000e6);

        LendingPoolV2 implV2 = new LendingPoolV2();
        pool.upgradeToAndCall(address(implV2), "");

        assertEq(pool.getCollateral(alice, address(usdc)), 1000e6);
    }

    function test_upgrade_revertsIfNotOwner() public {
        LendingPoolV2 implV2 = new LendingPoolV2();
        vm.prank(alice);
        vm.expectRevert();
        pool.upgradeToAndCall(address(implV2), "");
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    function test_addSupportedToken() public {
        address newToken = makeAddr("token");
        pool.addSupportedToken(newToken);
        assertTrue(pool.supportedTokens(newToken));
    }

    function test_addSupportedToken_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        pool.addSupportedToken(makeAddr("token"));
    }

    function test_setOracle() public {
        MockOracle newOracle = new MockOracle();
        pool.setOracle(address(newOracle));
        assertEq(address(pool.oracle()), address(newOracle));
    }

    function test_getTokenList() public view {
        address[] memory list = pool.getTokenList();
        assertEq(list.length, 2);
        assertEq(list[0], address(usdc));
        assertEq(list[1], address(weth));
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    function _depositAndBorrow(address user, uint256 depositAmount, address borrowToken, uint256 borrowAmount)
        internal
    {
        // Ensure liquidity exists
        vm.prank(bob);
        pool.deposit(address(usdc), depositAmount * 2);

        vm.prank(user);
        pool.deposit(address(usdc), depositAmount);
        vm.prank(user);
        pool.borrow(borrowToken, borrowAmount);
    }

    function _setupLiquidatablePosition() internal {
        // Alice deposits 1 WETH ($2000) and borrows 1400 USDC (70% LTV — within limit)
        vm.prank(bob);
        pool.deposit(address(usdc), 10000e6); // provide USDC liquidity

        vm.prank(alice);
        pool.deposit(address(weth), 1e18); // 1 WETH = $2000 collateral

        vm.prank(alice);
        pool.borrow(address(usdc), 1400e6); // borrow $1400 USDC

        // Drop WETH price to $1500 → collateral value 1500e18, debt value 1400e30/1e18=1400e12...
        // Need HF < 1e18: WETH value = 1e18 * wethPrice / 1e18 = wethPrice
        // USDC value = 1400e6 * 1e30 / 1e18 = 1400e18
        // HF = wethPrice * 80 / 100 / 1400e18 < 1e18 → wethPrice < 1400e18 * 100/80 = 1750e18
        oracle.setPrice(address(weth), 1500e18);
    }
}
