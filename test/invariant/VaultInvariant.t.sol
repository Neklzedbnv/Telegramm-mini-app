// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/vault/YieldVault.sol";
import "../../contracts/mocks/MockERC20.sol";

/// @dev Stateful handler for vault invariant testing — drives deposits, redeems, and yield accrual
contract VaultHandler is Test {
    YieldVault public vault;
    MockERC20 public asset;
    address public admin;

    address[] private _actors;

    // Ghost variables for invariant cross-checks
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public totalYieldAccrued;

    constructor(YieldVault vault_, MockERC20 asset_, address admin_) {
        vault = vault_;
        asset = asset_;
        admin = admin_;

        _actors.push(makeAddr("actor0"));
        _actors.push(makeAddr("actor1"));
        _actors.push(makeAddr("actor2"));

        for (uint256 i; i < _actors.length; i++) {
            asset.mint(_actors[i], 10_000_000e6);
            vm.prank(_actors[i]);
            asset.approve(address(vault), type(uint256).max);
        }
    }

    function actors() external view returns (address[] memory) {
        return _actors;
    }

    function deposit(uint256 actorSeed, uint256 assets) external {
        address actor = _actors[actorSeed % _actors.length];
        assets = bound(assets, 1, 1_000_000e6);

        uint256 bal = asset.balanceOf(actor);
        if (bal < assets) {
            asset.mint(actor, assets - bal);
        }

        vm.prank(actor);
        vault.deposit(assets, actor);
        totalDeposited += assets;
    }

    function redeem(uint256 actorSeed, uint256 sharesFrac) external {
        address actor = _actors[actorSeed % _actors.length];
        uint256 shares = vault.balanceOf(actor);
        if (shares == 0) return;
        shares = bound(sharesFrac, 1, shares);

        vm.prank(actor);
        uint256 assetsOut = vault.redeem(shares, actor, actor);
        totalWithdrawn += assetsOut;
    }

    function accrueYield(uint256 amount) external {
        amount = bound(amount, 1, 100_000e18);
        vm.prank(admin);
        vault.accrueYield(amount);
        totalYieldAccrued += amount;
    }
}

contract VaultInvariantTest is Test {
    YieldVault vault;
    MockERC20 asset;
    VaultHandler handler;
    address admin = makeAddr("admin");

    function setUp() public {
        asset = new MockERC20("USDC", "USDC", 6);
        vm.prank(admin);
        vault = new YieldVault(IERC20(address(asset)), address(0), admin);
        handler = new VaultHandler(vault, asset, admin);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = VaultHandler.deposit.selector;
        selectors[1] = VaultHandler.redeem.selector;
        selectors[2] = VaultHandler.accrueYield.selector;
        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    }

    // ─── Invariant I1 ─────────────────────────────────────────────────────────
    /// @notice Total redeemable assets never exceed totalAssets (no insolvent vault)
    function invariant_I1_totalAssets_geq_redeemableValue() public view {
        uint256 supply = vault.totalSupply();
        if (supply == 0) return;
        // convertToAssets of ALL shares — must be <= totalAssets (with 1 wei rounding tolerance)
        uint256 maxRedeemable = vault.convertToAssets(supply);
        assertLe(maxRedeemable, vault.totalAssets() + 1);
    }

    // ─── Invariant I2 ─────────────────────────────────────────────────────────
    /// @notice totalAssets() always equals the sum of its three components
    function invariant_I2_totalAssets_equalsComponents() public view {
        uint256 expected = asset.balanceOf(address(vault)) + vault.accruedYield() + vault.deployedAssets();
        assertEq(vault.totalAssets(), expected);
    }

    // ─── Invariant I3 ─────────────────────────────────────────────────────────
    /// @notice No individual user's share balance exceeds total supply
    function invariant_I3_noHolderExceedsTotalSupply() public view {
        address[] memory actors_ = handler.actors();
        uint256 supply = vault.totalSupply();
        for (uint256 i; i < actors_.length; i++) {
            assertLe(vault.balanceOf(actors_[i]), supply);
        }
    }

    // ─── Invariant I4 ─────────────────────────────────────────────────────────
    /// @notice Round-trip conversion (shares → assets → shares) never inflates shares
    function invariant_I4_shareRoundTrip_conservative() public view {
        uint256 supply = vault.totalSupply();
        if (supply == 0) return;
        uint256 testShares = supply < 1000 ? supply : 1000;
        uint256 assets = vault.convertToAssets(testShares);
        if (assets == 0) return;
        uint256 sharesBack = vault.convertToShares(assets);
        assertLe(sharesBack, testShares);
    }

    // ─── Invariant I5 ─────────────────────────────────────────────────────────
    /// @notice Ghost accounting: total deposited minus total withdrawn + accrued yield == totalAssets
    ///         (modulo the initial zero-supply state where totalAssets may be zero)
    function invariant_I5_ghostAccountingConsistency() public view {
        // totalDeposited - totalWithdrawn + accruedYield == totalAssets
        // Since redeems can return slightly less due to rounding, we check with tolerance
        uint256 vaultAssets = vault.totalAssets();
        uint256 ghostExpected = handler.totalDeposited() + handler.totalYieldAccrued();
        uint256 ghostWithdrawn = handler.totalWithdrawn();

        if (ghostExpected >= ghostWithdrawn) {
            uint256 netGhost = ghostExpected - ghostWithdrawn;
            // Allow 1-wei-per-actor rounding tolerance
            assertLe(vaultAssets, netGhost + 10);
            assertGe(vaultAssets + 10, netGhost);
        }
    }
}
