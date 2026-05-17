// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../contracts/core/LendingPoolV1.sol";
import "../../contracts/core/LendingPoolV2.sol";
import "../../contracts/mocks/MockERC20.sol";
import "../../contracts/mocks/MockOracle.sol";
import "../../contracts/mocks/MockFlashLoanReceiver.sol";

/// @dev Tests for V2-specific functionality: initializeV2, setFlashLoanFee,
///      withdrawFlashLoanFees, and flash loan edge cases.
contract LendingPoolV2Test is Test {
    LendingPoolV2 pool;
    MockOracle oracle;
    MockERC20 usdc;
    MockFlashLoanReceiver receiver;

    address owner = address(this);
    address alice = makeAddr("alice");

    function setUp() public {
        vm.warp(100_000);

        oracle = new MockOracle();
        oracle.setPrice(address(0), 0);

        // Deploy as V1 first, then upgrade to V2
        LendingPoolV1 implV1 = new LendingPoolV1();
        bytes memory initData = abi.encodeCall(LendingPoolV1.initialize, (address(oracle), owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implV1), initData);
        LendingPoolV1 poolV1 = LendingPoolV1(address(proxy));

        usdc = new MockERC20("USDC", "USDC", 6);
        oracle.setPrice(address(usdc), 1e30);
        poolV1.addSupportedToken(address(usdc));

        // Upgrade to V2
        LendingPoolV2 implV2 = new LendingPoolV2();
        poolV1.upgradeToAndCall(address(implV2), "");
        pool = LendingPoolV2(address(proxy));

        receiver = new MockFlashLoanReceiver(address(pool));

        // Fund pool with liquidity
        usdc.mint(owner, 100_000e6);
        usdc.approve(address(pool), type(uint256).max);
        pool.deposit(address(usdc), 50_000e6);

        // Fund receiver so it can repay flash loans
        usdc.mint(address(receiver), 10_000e6);

        usdc.mint(alice, 10_000e6);
        vm.prank(alice);
        usdc.approve(address(pool), type(uint256).max);
    }

    // ─── initializeV2 ─────────────────────────────────────────────────────────

    function test_initializeV2_setsFeeBps() public {
        LendingPoolV2 impl2 = new LendingPoolV2();
        bytes memory initData = abi.encodeCall(LendingPoolV1.initialize, (address(oracle), owner));
        LendingPoolV2 pool2 = LendingPoolV2(address(new ERC1967Proxy(address(impl2), initData)));
        pool2.initializeV2(50);
        assertEq(pool2.flashLoanFeeBps(), 50);
    }

    function test_initializeV2_revertsFeeTooHigh() public {
        LendingPoolV2 impl2 = new LendingPoolV2();
        bytes memory initData = abi.encodeCall(LendingPoolV1.initialize, (address(oracle), owner));
        LendingPoolV2 pool2 = LendingPoolV2(address(new ERC1967Proxy(address(impl2), initData)));
        vm.expectRevert(abi.encodeWithSelector(LendingPoolV2.FeeTooHigh.selector, 501, 500));
        pool2.initializeV2(501);
    }

    function test_initializeV2_revertsIfCalledTwice() public {
        LendingPoolV2 impl2 = new LendingPoolV2();
        bytes memory initData = abi.encodeCall(LendingPoolV1.initialize, (address(oracle), owner));
        LendingPoolV2 pool2 = LendingPoolV2(address(new ERC1967Proxy(address(impl2), initData)));
        pool2.initializeV2(10);
        vm.expectRevert();
        pool2.initializeV2(10);
    }

    // ─── setFlashLoanFee ──────────────────────────────────────────────────────

    function test_setFlashLoanFee_updatesValue() public {
        pool.setFlashLoanFee(100);
        assertEq(pool.flashLoanFeeBps(), 100);
    }

    function test_setFlashLoanFee_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit LendingPoolV2.FlashLoanFeeUpdated(0, 100);
        pool.setFlashLoanFee(100);
    }

    function test_setFlashLoanFee_revertsIfTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(LendingPoolV2.FeeTooHigh.selector, 501, 500));
        pool.setFlashLoanFee(501);
    }

    function test_setFlashLoanFee_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        pool.setFlashLoanFee(100);
    }

    function test_setFlashLoanFee_maxAllowed() public {
        pool.setFlashLoanFee(500);
        assertEq(pool.flashLoanFeeBps(), 500);
    }

    // ─── withdrawFlashLoanFees ────────────────────────────────────────────────

    function test_withdrawFlashLoanFees_afterLoan() public {
        pool.setFlashLoanFee(100); // 1%
        pool.flashLoan(address(usdc), 1000e6, address(receiver), "");
        uint256 fee = (1000e6 * 100) / 10_000;

        uint256 balBefore = usdc.balanceOf(alice);
        pool.withdrawFlashLoanFees(address(usdc), alice);
        assertEq(usdc.balanceOf(alice), balBefore + fee);
    }

    function test_withdrawFlashLoanFees_resetsToZero() public {
        pool.setFlashLoanFee(100);
        pool.flashLoan(address(usdc), 1000e6, address(receiver), "");
        pool.withdrawFlashLoanFees(address(usdc), alice);
        assertEq(pool.flashLoanFees(address(usdc)), 0);
    }

    function test_withdrawFlashLoanFees_emitsEvent() public {
        pool.setFlashLoanFee(100);
        pool.flashLoan(address(usdc), 1000e6, address(receiver), "");
        uint256 fee = (1000e6 * 100) / 10_000;
        vm.expectEmit(true, true, false, true);
        emit LendingPoolV2.FlashLoanFeesWithdrawn(address(usdc), fee, alice);
        pool.withdrawFlashLoanFees(address(usdc), alice);
    }

    function test_withdrawFlashLoanFees_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        pool.withdrawFlashLoanFees(address(usdc), alice);
    }

    // ─── flashLoan edge cases ─────────────────────────────────────────────────

    function test_flashLoan_revertsUnsupportedToken() public {
        address fake = makeAddr("fake");
        vm.expectRevert(abi.encodeWithSelector(LendingPoolV2.TokenNotSupportedForFlashLoan.selector, fake));
        pool.flashLoan(fake, 100, address(receiver), "");
    }

    function test_flashLoan_revertsZeroAmount() public {
        vm.expectRevert(LendingPoolV1.ZeroAmount.selector);
        pool.flashLoan(address(usdc), 0, address(receiver), "");
    }

    function test_flashLoan_revertsInsufficientLiquidity() public {
        vm.expectRevert();
        pool.flashLoan(address(usdc), 100_000e6, address(receiver), ""); // more than available
    }

    function test_flashLoan_withFee_accruesFees() public {
        pool.setFlashLoanFee(50); // 0.5%
        pool.flashLoan(address(usdc), 10_000e6, address(receiver), "");
        uint256 expectedFee = (10_000e6 * 50) / 10_000;
        assertEq(pool.flashLoanFees(address(usdc)), expectedFee);
    }

    function test_flashLoan_emitsEvent() public {
        pool.setFlashLoanFee(100);
        vm.expectEmit(true, false, true, false);
        emit LendingPoolV2.FlashLoanExecuted(address(usdc), 1000e6, 0, address(receiver), owner);
        pool.flashLoan(address(usdc), 1000e6, address(receiver), "");
    }

    function test_flashLoan_version() public view {
        assertEq(pool.version(), "2.0.0");
    }
}
