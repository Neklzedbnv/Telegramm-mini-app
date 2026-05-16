// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/YieldVault.sol";
import "../../src/LendingPool.sol";
import "../../src/mocks/MockERC20.sol";
import "../../src/mocks/MockOracle.sol";

contract YieldVaultTest is Test {
    YieldVault vault;
    LendingPool pool;
    MockERC20 usdc;
    MockOracle oracle;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address owner = address(this);

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        oracle = new MockOracle();
        oracle.setPrice(address(usdc), 1e30); // USDC 6 decimals: $1/token → 1e30

        LendingPool impl = new LendingPool();
        bytes memory initData = abi.encodeCall(LendingPool.initialize, (address(oracle), owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        pool = LendingPool(address(proxy));
        pool.addSupportedToken(address(usdc));

        vault = new YieldVault(IERC20(address(usdc)), address(pool), owner);

        usdc.mint(alice, 10_000e6);
        usdc.mint(bob, 10_000e6);
        usdc.mint(owner, 100_000e6);

        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
    }

    // ─── Deposit ──────────────────────────────────────────────────────────────

    function test_vault_deposit_receiveShares() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1000e6, alice);
        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
    }

    function test_vault_deposit_firstDeposit_1to1() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1000e6, alice);
        assertEq(shares, 1000e6);
    }

    function test_vault_deposit_emitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(false, false, false, false);
        emit IERC4626.Deposit(alice, alice, 0, 0);
        vault.deposit(1000e6, alice);
    }

    function test_vault_deposit_differentReceiver() public {
        vm.prank(alice);
        vault.deposit(1000e6, bob);
        assertEq(vault.balanceOf(bob), 1000e6);
        assertEq(vault.balanceOf(alice), 0);
    }

    // ─── Mint ─────────────────────────────────────────────────────────────────

    function test_vault_mint_byShares() public {
        vm.prank(alice);
        uint256 assets = vault.mint(1000e6, alice);
        assertEq(assets, 1000e6);
        assertEq(vault.balanceOf(alice), 1000e6);
    }

    function test_vault_mint_afterYield_moreAssets() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);

        usdc.mint(address(vault), 500e6); // +50% yield via real tokens

        vm.prank(bob);
        uint256 assetsNeeded = vault.mint(1000e6, bob);
        // Bob needs more assets to get same shares (price per share increased)
        assertGt(assetsNeeded, 1000e6);
    }

    // ─── Withdraw ─────────────────────────────────────────────────────────────

    function test_vault_withdraw_assets() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);

        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(500e6, alice, alice);
        assertEq(usdc.balanceOf(alice), balBefore + 500e6);
    }

    function test_vault_withdraw_burnsShares() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        uint256 sharesBefore = vault.balanceOf(alice);

        vm.prank(alice);
        vault.withdraw(500e6, alice, alice);
        assertLt(vault.balanceOf(alice), sharesBefore);
    }

    // ─── Redeem ───────────────────────────────────────────────────────────────

    function test_vault_redeem_byShares() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);

        vm.prank(alice);
        uint256 assets = vault.redeem(500e6, alice, alice);
        assertEq(assets, 500e6);
    }

    function test_vault_redeem_afterYield_moreAssets() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);

        // Simulate yield by minting real tokens to vault (realistic yield deposit)
        usdc.mint(address(vault), 1000e6); // vault now has 2000e6 balance → 2x share price

        vm.prank(alice);
        uint256 assets = vault.redeem(1000e6, alice, alice);
        // ERC4626 rounds down by 1 wei for security
        assertApproxEqAbs(assets, 2000e6, 1);
    }

    // ─── totalAssets ──────────────────────────────────────────────────────────

    function test_vault_totalAssets_empty() public view {
        assertEq(vault.totalAssets(), 0);
    }

    function test_vault_totalAssets_afterDeposit() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        assertEq(vault.totalAssets(), 1000e6);
    }

    function test_vault_totalAssets_includesYield() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        usdc.mint(address(vault), 200e6); // yield as real tokens
        assertEq(vault.totalAssets(), 1200e6);
    }

    // ─── convertTo ────────────────────────────────────────────────────────────

    function test_vault_convertToShares_1to1Initially() public view {
        assertEq(vault.convertToShares(1000e6), 1000e6);
    }

    function test_vault_convertToAssets_1to1Initially() public view {
        assertEq(vault.convertToAssets(1000e6), 1000e6);
    }

    function test_vault_convertToShares_afterYield() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);
        usdc.mint(address(vault), 1000e6); // 100% yield → share price = 2

        uint256 shares = vault.convertToShares(2000e6);
        assertEq(shares, 1000e6); // 2000 assets = 1000 shares
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    function test_vault_setLendingPool() public {
        address newPool = makeAddr("newPool");
        vault.setLendingPool(newPool);
        assertEq(address(vault.lendingPool()), newPool);
    }

    function test_vault_setLendingPool_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setLendingPool(makeAddr("pool"));
    }

    function test_vault_accrueYield_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.accrueYield(100e6);
    }

    function test_vault_depositToLendingPool() public {
        vm.prank(alice);
        vault.deposit(1000e6, alice);

        // Pool needs to have usdc deposited by vault
        usdc.approve(address(pool), type(uint256).max);
        vault.depositToLendingPool(500e6);

        assertEq(pool.getCollateral(address(vault), address(usdc)), 500e6);
    }
}
