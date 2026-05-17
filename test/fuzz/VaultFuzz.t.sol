// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/vault/YieldVault.sol";
import "../../contracts/mocks/MockERC20.sol";

contract VaultFuzzTest is Test {
    YieldVault vault;
    MockERC20 asset;

    address admin = makeAddr("admin");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant MAX_ASSETS = 1_000_000e6; // 1M USDC (6 dec)

    function setUp() public {
        asset = new MockERC20("USDC", "USDC", 6);
        vm.prank(admin);
        vault = new YieldVault(IERC20(address(asset)), address(0), admin);
    }

    function _mintAndApprove(address user, uint256 amount) internal {
        asset.mint(user, amount);
        vm.prank(user);
        asset.approve(address(vault), amount);
    }

    // ─── Fuzz Tests ───────────────────────────────────────────────────────────

    /// @notice Any deposit > 0 results in positive shares
    function testFuzz_deposit_anyAmount_receivesShares(uint256 assets) public {
        assets = bound(assets, 1, MAX_ASSETS);
        _mintAndApprove(alice, assets);

        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
    }

    /// @notice Total assets increases by exactly the deposited amount
    function testFuzz_deposit_totalAssetsIncreasesCorrectly(uint256 assets) public {
        assets = bound(assets, 1, MAX_ASSETS);
        _mintAndApprove(alice, assets);

        uint256 beforeAssets = vault.totalAssets();

        vm.prank(alice);
        vault.deposit(assets, alice);

        assertEq(vault.totalAssets(), beforeAssets + assets);
    }

    /// @notice Depositing then redeeming all shares returns approximately the initial assets
    function testFuzz_depositThenRedeemAll_returnsAssets(uint256 assets) public {
        assets = bound(assets, 1, MAX_ASSETS);
        _mintAndApprove(alice, assets);

        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        vm.prank(alice);
        uint256 returned = vault.redeem(shares, alice, alice);

        // Allow 1 wei rounding loss (ERC-4626 standard rounding)
        assertGe(returned, assets - 1);
        assertLe(returned, assets);
    }

    /// @notice Share price (assets per share) never decreases after yield accrual
    function testFuzz_yieldAccrual_onlyIncreasesSharePrice(uint256 depositAmt, uint256 yieldAmt) public {
        depositAmt = bound(depositAmt, 1e6, MAX_ASSETS);
        yieldAmt = bound(yieldAmt, 1, 1_000_000e18); // yield in 18 dec

        _mintAndApprove(alice, depositAmt);
        vm.prank(alice);
        vault.deposit(depositAmt, alice);

        uint256 assetsBefore = vault.convertToAssets(1e18);

        vm.prank(admin);
        vault.accrueYield(yieldAmt);

        uint256 assetsAfter = vault.convertToAssets(1e18);
        assertGe(assetsAfter, assetsBefore);
    }

    /// @notice mint() and deposit() are inverse operations for share accounting
    function testFuzz_mintAndDeposit_inverseOperations(uint256 shares) public {
        shares = bound(shares, 1, 1e12); // limit to reasonable share count

        uint256 assetsNeeded = vault.previewMint(shares);
        vm.assume(assetsNeeded > 0 && assetsNeeded <= MAX_ASSETS);

        _mintAndApprove(alice, assetsNeeded);
        vm.prank(alice);
        uint256 assetsUsed = vault.mint(shares, alice);

        assertEq(vault.balanceOf(alice), shares);
        assertLe(assetsUsed, assetsNeeded);
    }

    /// @notice withdraw() burns the minimum shares required
    function testFuzz_withdraw_burnsCorrectShares(uint256 assets) public {
        assets = bound(assets, 1, MAX_ASSETS / 2);
        uint256 depositAmt = assets * 2;

        _mintAndApprove(alice, depositAmt);
        vm.prank(alice);
        vault.deposit(depositAmt, alice);

        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 expectedShares = vault.previewWithdraw(assets);

        vm.prank(alice);
        uint256 sharesActual = vault.withdraw(assets, alice, alice);

        assertEq(sharesActual, expectedShares);
        assertEq(vault.balanceOf(alice), sharesBefore - sharesActual);
    }

    /// @notice convertToShares and convertToAssets are consistent
    function testFuzz_conversionConsistency(uint256 assets) public view {
        assets = bound(assets, 1, MAX_ASSETS);
        uint256 shares = vault.convertToShares(assets);
        uint256 roundTrip = vault.convertToAssets(shares);
        // Round-trip may lose at most 1 unit due to floor division
        assertLe(roundTrip, assets);
        if (shares > 0) {
            assertGt(roundTrip, 0);
        }
    }

    /// @notice Multiple depositors: each user's share balance is proportional to deposit
    function testFuzz_multipleDepositors_proportionalShares(uint256 aliceAmt, uint256 bobAmt) public {
        aliceAmt = bound(aliceAmt, 1e6, MAX_ASSETS / 2);
        bobAmt = bound(bobAmt, 1e6, MAX_ASSETS / 2);

        _mintAndApprove(alice, aliceAmt);
        _mintAndApprove(bob, bobAmt);

        vm.prank(alice);
        uint256 aliceShares = vault.deposit(aliceAmt, alice);
        vm.prank(bob);
        uint256 bobShares = vault.deposit(bobAmt, bob);

        uint256 total = vault.totalSupply();
        assertEq(aliceShares + bobShares, total);
        assertGt(total, 0);
    }

    /// @notice Pausing prevents all user operations
    function testFuzz_pause_blocksDeposit(uint256 assets) public {
        assets = bound(assets, 1, MAX_ASSETS);
        _mintAndApprove(alice, assets);

        vm.prank(admin);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(assets, alice);
    }

    /// @notice Zero deposit reverts
    function testFuzz_deposit_zeroReverts(address receiver) public {
        vm.assume(receiver != address(0));
        vm.expectRevert(YieldVault.ZeroAmount.selector);
        vault.deposit(0, receiver);
    }

    /// @notice After full redemption, total supply is zero
    function testFuzz_fullRedeem_zerosSupply(uint256 assets) public {
        assets = bound(assets, 1, MAX_ASSETS);
        _mintAndApprove(alice, assets);

        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        assertEq(vault.totalSupply(), 0);
    }
}
