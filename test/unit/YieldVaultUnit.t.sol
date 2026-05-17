// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "../../contracts/vault/YieldVault.sol";
import "../../contracts/core/LendingPoolV1.sol";
import "../../contracts/mocks/MockERC20.sol";
import "../../contracts/mocks/MockOracle.sol";

contract YieldVaultUnitTest is Test {
    YieldVault vault;
    LendingPoolV1 pool;
    MockERC20 usdc;
    MockOracle oracle;

    address admin = address(this);
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        oracle = new MockOracle();
        oracle.setPrice(address(usdc), 1e30);

        LendingPoolV1 impl = new LendingPoolV1();
        bytes memory initData = abi.encodeCall(LendingPoolV1.initialize, (address(oracle), admin));
        pool = LendingPoolV1(address(new ERC1967Proxy(address(impl), initData)));
        pool.addSupportedToken(address(usdc));

        vault = new YieldVault(IERC20(address(usdc)), address(pool), admin);

        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);
        usdc.mint(admin, 100_000e6);

        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
    }

    // ─── Deposit ──────────────────────────────────────────────────────────────

    function test_deposit_receivesShares() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1000e6, alice);
        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
    }

    function test_deposit_firstDeposit_1to1() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1000e6, alice);
        assertEq(shares, 1000e6);
    }

    function test_deposit_differentReceiver() public {
        vm.prank(alice);
        vault.deposit(1000e6, bob);
        assertEq(vault.balanceOf(bob), 1000e6);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_deposit_revertsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(YieldVault.ZeroAmount.selector);
        vault.deposit(0, alice);
    }

    function test_deposit_revertsWhenPaused() public {
        vault.pause();
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(1000e6, alice);
    }

    function test_deposit_emitsERC4626Event() public {
        vm.prank(alice);
        vm.expectEmit(false, false, false, false);
        emit IERC4626.Deposit(alice, alice, 0, 0);
        vault.deposit(1000e6, alice);
    }

    // ─── Mint ─────────────────────────────────────────────────────────────────

    function test_mint_byShares() public {
        vm.prank(alice);
        uint256 assets = vault.mint(1000e6, alice);
        assertEq(assets, 1000e6);
        assertEq(vault.balanceOf(alice), 1000e6);
    }

    function test_mint_revertsZeroShares() public {
        vm.prank(alice);
        vm.expectRevert(YieldVault.ZeroAmount.selector);
        vault.mint(0, alice);
    }

    function test_mint_revertsWhenPaused() public {
        vault.pause();
        vm.prank(alice);
        vm.expectRevert();
        vault.mint(1000e6, alice);
    }

    function test_mint_afterYield_costsMoreAssets() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        usdc.mint(address(vault), 1000e6); // 100% yield
        vm.prank(bob);
        uint256 assets = vault.mint(1000e6, bob);
        assertGt(assets, 1000e6);
    }

    // ─── Withdraw ─────────────────────────────────────────────────────────────

    function test_withdraw_returnsAssets() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(500e6, alice, alice);
        assertEq(usdc.balanceOf(alice), balBefore + 500e6);
    }

    function test_withdraw_burnsShares() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        uint256 sharesBefore = vault.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(500e6, alice, alice);
        assertLt(vault.balanceOf(alice), sharesBefore);
    }

    function test_withdraw_revertsZeroAmount() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        vm.prank(alice);
        vm.expectRevert(YieldVault.ZeroAmount.selector);
        vault.withdraw(0, alice, alice);
    }

    function test_withdraw_revertsWhenPaused() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        vault.pause();
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(500e6, alice, alice);
    }

    // ─── Redeem ───────────────────────────────────────────────────────────────

    function test_redeem_byShares() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        vm.prank(alice);
        uint256 assets = vault.redeem(500e6, alice, alice);
        assertEq(assets, 500e6);
    }

    function test_redeem_afterYield_moreAssets() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        usdc.mint(address(vault), 1000e6);
        vm.prank(alice);
        uint256 assets = vault.redeem(1000e6, alice, alice);
        assertApproxEqAbs(assets, 2000e6, 1);
    }

    function test_redeem_revertsZeroShares() public {
        vm.prank(alice);
        vm.expectRevert(YieldVault.ZeroAmount.selector);
        vault.redeem(0, alice, alice);
    }

    function test_redeem_revertsWhenPaused() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        vault.pause();
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(500e6, alice, alice);
    }

    // ─── totalAssets ──────────────────────────────────────────────────────────

    function test_totalAssets_empty() public view {
        assertEq(vault.totalAssets(), 0);
    }

    function test_totalAssets_afterDeposit() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        assertEq(vault.totalAssets(), 1000e6);
    }

    function test_totalAssets_includesAccruedYield() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        vault.accrueYield(200e6);
        assertEq(vault.totalAssets(), 1200e6);
    }

    function test_totalAssets_includesDeployedAssets() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        vault.deployToLendingPool(500e6);
        assertEq(vault.totalAssets(), 1000e6);
    }

    // ─── convertTo ────────────────────────────────────────────────────────────

    function test_convertToShares_1to1Initially() public view {
        assertEq(vault.convertToShares(1000e6), 1000e6);
    }

    function test_convertToAssets_1to1Initially() public view {
        assertEq(vault.convertToAssets(1000e6), 1000e6);
    }

    function test_convertToShares_afterYield_fewer() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        usdc.mint(address(vault), 1000e6); // share price = 2
        assertEq(vault.convertToShares(2000e6), 1000e6);
    }

    // ─── Pause / Unpause ──────────────────────────────────────────────────────

    function test_pause_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.pause();
    }

    function test_unpause_onlyAdmin() public {
        vault.pause();
        vm.prank(alice);
        vm.expectRevert();
        vault.unpause();
    }

    function test_unpause_restoresDeposit() public {
        vault.pause();
        vault.unpause();
        vm.prank(alice);
        uint256 shares = vault.deposit(1000e6, alice);
        assertGt(shares, 0);
    }

    // ─── setLendingPool ───────────────────────────────────────────────────────

    function test_setLendingPool_updatesAddress() public {
        address newPool = makeAddr("newPool");
        vault.setLendingPool(newPool);
        assertEq(address(vault.lendingPool()), newPool);
    }

    function test_setLendingPool_emitsEvent() public {
        address newPool = makeAddr("newPool");
        vm.expectEmit(true, true, false, false);
        emit YieldVault.LendingPoolUpdated(address(pool), newPool);
        vault.setLendingPool(newPool);
    }

    function test_setLendingPool_revertsIfNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setLendingPool(makeAddr("pool"));
    }

    // ─── accrueYield ──────────────────────────────────────────────────────────

    function test_accrueYield_increasesAccruedYield() public {
        vault.accrueYield(500e6);
        assertEq(vault.accruedYield(), 500e6);
    }

    function test_accrueYield_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit YieldVault.YieldAccrued(admin, 500e6);
        vault.accrueYield(500e6);
    }

    function test_accrueYield_revertsZeroAmount() public {
        vm.expectRevert(YieldVault.ZeroAmount.selector);
        vault.accrueYield(0);
    }

    function test_accrueYield_revertsIfNotManager() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.accrueYield(100e6);
    }

    // ─── deployToLendingPool ──────────────────────────────────────────────────

    function test_deployToLendingPool_transfersToPool() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        vault.deployToLendingPool(500e6);
        assertEq(pool.getCollateral(address(vault), address(usdc)), 500e6);
        assertEq(vault.deployedAssets(), 500e6);
    }

    function test_deployToLendingPool_emitsEvent() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        vm.expectEmit(false, false, false, true);
        emit YieldVault.AssetsDeployedToPool(500e6);
        vault.deployToLendingPool(500e6);
    }

    function test_deployToLendingPool_revertsZeroAmount() public {
        vm.expectRevert(YieldVault.ZeroAmount.selector);
        vault.deployToLendingPool(0);
    }

    function test_deployToLendingPool_revertsIfPoolNotSet() public {
        YieldVault vaultNoPool = new YieldVault(IERC20(address(usdc)), address(0), admin);
        usdc.mint(address(vaultNoPool), 1000e6);
        vm.expectRevert(YieldVault.LendingPoolNotSet.selector);
        vaultNoPool.deployToLendingPool(100e6);
    }

    function test_deployToLendingPool_revertsIfNotManager() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.deployToLendingPool(100e6);
    }

    // ─── recallFromLendingPool ────────────────────────────────────────────────

    function test_recallFromLendingPool_withdrawsFromPool() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        vault.deployToLendingPool(500e6);
        vault.recallFromLendingPool(300e6);
        assertEq(vault.deployedAssets(), 200e6);
    }

    function test_recallFromLendingPool_emitsEvent() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        vault.deployToLendingPool(500e6);
        vm.expectEmit(false, false, false, true);
        emit YieldVault.AssetsWithdrawnFromPool(300e6);
        vault.recallFromLendingPool(300e6);
    }

    function test_recallFromLendingPool_revertsZeroAmount() public {
        vm.expectRevert(YieldVault.ZeroAmount.selector);
        vault.recallFromLendingPool(0);
    }

    function test_recallFromLendingPool_revertsIfInsufficientDeployed() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        vault.deployToLendingPool(300e6);
        vm.expectRevert();
        vault.recallFromLendingPool(500e6);
    }

    function test_recallFromLendingPool_revertsIfPoolNotSet() public {
        YieldVault vaultNoPool = new YieldVault(IERC20(address(usdc)), address(0), admin);
        vm.expectRevert(YieldVault.LendingPoolNotSet.selector);
        vaultNoPool.recallFromLendingPool(100e6);
    }

    function test_recallFromLendingPool_revertsIfNotManager() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.recallFromLendingPool(100e6);
    }

    // ─── supportsInterface ────────────────────────────────────────────────────

    function test_supportsInterface_accessControl() public view {
        assertTrue(vault.supportsInterface(type(IAccessControl).interfaceId));
    }
}
