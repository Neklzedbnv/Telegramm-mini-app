// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../contracts/core/LendingPoolV1.sol";
import "../../contracts/core/LendingPoolV2.sol";
import "../../contracts/mocks/MockERC20.sol";
import "../../contracts/mocks/MockOracle.sol";
import "../../contracts/mocks/MockFlashLoanReceiver.sol";

contract LendingPoolV1Test is Test {
    LendingPoolV1 pool;
    MockOracle oracle;
    MockERC20 usdc;
    MockERC20 weth;

    address owner = address(this);
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address liquidator = makeAddr("liquidator");

    // USDC (6 dec): $1 → price = 1e30 (since value = amount * price / 1e18)
    uint256 constant USDC_PRICE = 1e30;
    // WETH (18 dec): $2000 → price = 2000e18
    uint256 constant WETH_PRICE = 2000e18;
    uint256 constant PRECISION = 1e18;

    function setUp() public {
        oracle = new MockOracle();
        LendingPoolV1 impl = new LendingPoolV1();
        bytes memory initData = abi.encodeCall(LendingPoolV1.initialize, (address(oracle), address(this)));
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
    }

    // ─── Initialization ───────────────────────────────────────────────────────

    function test_v1_initialVersion() public view {
        assertEq(pool.version(), "1.0.0");
    }

    function test_v1_oracleSet() public view {
        assertEq(address(pool.oracle()), address(oracle));
    }

    function test_v1_ownerSet() public view {
        assertEq(pool.owner(), address(this));
    }

    function test_v1_initializer_revertsIfCalledAgain() public {
        vm.expectRevert();
        pool.initialize(address(oracle), address(this));
    }

    function test_v1_initialize_revertsZeroOracle() public {
        LendingPoolV1 impl = new LendingPoolV1();
        bytes memory initData = abi.encodeCall(LendingPoolV1.initialize, (address(0), address(this)));
        vm.expectRevert();
        new ERC1967Proxy(address(impl), initData);
    }

    // ─── Token Management ─────────────────────────────────────────────────────

    function test_addToken_emitsEvent() public {
        MockERC20 newToken = new MockERC20("DAI", "DAI", 18);
        vm.expectEmit(true, false, false, false);
        emit ILendingPool.TokenAdded(address(newToken));
        pool.addSupportedToken(address(newToken));
    }

    function test_addToken_idempotent() public {
        pool.addSupportedToken(address(usdc));
        assertEq(pool.getTokenList().length, 2); // still 2, not 3
    }

    function test_setOracle_updatesOracle() public {
        MockOracle newOracle = new MockOracle();
        pool.setOracle(address(newOracle));
        assertEq(address(pool.oracle()), address(newOracle));
    }

    function test_setOracle_emitsEvent() public {
        MockOracle newOracle = new MockOracle();
        vm.expectEmit(true, false, false, false);
        emit ILendingPool.OracleUpdated(address(newOracle));
        pool.setOracle(address(newOracle));
    }

    function test_setOracle_revertsZeroAddress() public {
        vm.expectRevert(LendingPoolV1.ZeroAddress.selector);
        pool.setOracle(address(0));
    }

    // ─── Stale Oracle ─────────────────────────────────────────────────────────

    function test_stalePrice_revertsOnBorrow() public {
        // Alice deposits collateral first (price is fresh)
        vm.prank(alice);
        pool.deposit(address(usdc), 2000e6);

        vm.prank(bob);
        pool.deposit(address(usdc), 5000e6); // extra liquidity

        // Freeze oracle timestamp to more than 1 hour ago
        uint256 staleTs = block.timestamp - 2 hours;
        oracle.setTimestamp(address(usdc), staleTs);

        // Now price is stale — borrow should fail during health factor check
        vm.prank(alice);
        vm.expectRevert(LendingPoolV1.InvalidPrice.selector);
        pool.borrow(address(usdc), 100e6);
    }

    // ─── Upgrade to V2 ────────────────────────────────────────────────────────

    function test_upgrade_toV2_preservesVersion() public {
        LendingPoolV2 implV2 = new LendingPoolV2();
        pool.upgradeToAndCall(address(implV2), "");
        LendingPoolV2 poolV2 = LendingPoolV2(address(pool));
        assertEq(poolV2.version(), "2.0.0");
    }

    function test_upgrade_toV2_preservesState() public {
        vm.prank(alice);
        pool.deposit(address(usdc), 5000e6);

        LendingPoolV2 implV2 = new LendingPoolV2();
        pool.upgradeToAndCall(address(implV2), "");

        assertEq(pool.getCollateral(alice, address(usdc)), 5000e6);
        assertEq(pool.totalDeposits(address(usdc)), 5000e6);
    }

    function test_upgrade_toV2_preservesTokenList() public {
        LendingPoolV2 implV2 = new LendingPoolV2();
        pool.upgradeToAndCall(address(implV2), "");
        address[] memory list = pool.getTokenList();
        assertEq(list.length, 2);
    }

    function test_upgrade_revertsIfNotOwner() public {
        LendingPoolV2 implV2 = new LendingPoolV2();
        vm.prank(alice);
        vm.expectRevert();
        pool.upgradeToAndCall(address(implV2), "");
    }

    // ─── Flash Loan (V2) ──────────────────────────────────────────────────────

    function test_flashLoan_succeeds() public {
        // Upgrade to V2
        LendingPoolV2 implV2 = new LendingPoolV2();
        pool.upgradeToAndCall(address(implV2), "");
        LendingPoolV2 poolV2 = LendingPoolV2(address(pool));

        // Provide liquidity
        vm.prank(alice);
        pool.deposit(address(usdc), 10_000e6);

        // Deploy flash loan receiver with enough tokens to repay
        MockFlashLoanReceiver receiver = new MockFlashLoanReceiver(address(poolV2));
        usdc.mint(address(receiver), 1000e6); // pre-fund receiver for fee

        poolV2.flashLoan(address(usdc), 1000e6, address(receiver), "");

        assertEq(receiver.lastAmount(), 1000e6);
    }

    function test_flashLoan_revertsIfNotRepaid() public {
        LendingPoolV2 implV2 = new LendingPoolV2();
        pool.upgradeToAndCall(address(implV2), "");
        LendingPoolV2 poolV2 = LendingPoolV2(address(pool));

        vm.prank(alice);
        pool.deposit(address(usdc), 5000e6);

        MockFlashLoanReceiver receiver = new MockFlashLoanReceiver(address(poolV2));
        receiver.setShouldRepay(false);

        vm.expectRevert();
        poolV2.flashLoan(address(usdc), 1000e6, address(receiver), "");
    }
}
