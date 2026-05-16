// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/LendingPool.sol";
import "../../src/mocks/MockERC20.sol";
import "../../src/mocks/MockOracle.sol";

contract LendingFuzzTest is Test {
    LendingPool pool;
    MockERC20 usdc;
    MockOracle oracle;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant MAX_AMOUNT = 1_000_000e6;
    uint256 constant PRICE = 1e30; // USDC 6 decimals: $1/token → 1e30

    function setUp() public {
        oracle = new MockOracle();
        oracle.setPrice(address(0), 0);

        LendingPool impl = new LendingPool();
        bytes memory initData = abi.encodeCall(LendingPool.initialize, (address(oracle), address(this)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        pool = LendingPool(address(proxy));

        usdc = new MockERC20("USDC", "USDC", 6);
        oracle.setPrice(address(usdc), PRICE);
        pool.addSupportedToken(address(usdc));

        usdc.mint(alice, type(uint128).max);
        usdc.mint(bob, type(uint128).max);

        vm.prank(alice);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(pool), type(uint256).max);
    }

    function testFuzz_deposit_anyAmount(uint256 amount) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        vm.prank(alice);
        pool.deposit(address(usdc), amount);
        assertEq(pool.getCollateral(alice, address(usdc)), amount);
    }

    function testFuzz_deposit_totalDepositsAccumulates(uint256 a, uint256 b) public {
        a = bound(a, 1, MAX_AMOUNT);
        b = bound(b, 1, MAX_AMOUNT);
        vm.prank(alice);
        pool.deposit(address(usdc), a);
        vm.prank(bob);
        pool.deposit(address(usdc), b);
        assertEq(pool.totalDeposits(address(usdc)), a + b);
    }

    function testFuzz_borrow_withinLTV(uint256 depositAmount, uint256 borrowAmount) public {
        depositAmount = bound(depositAmount, 1000e6, MAX_AMOUNT);
        // Borrow at most 75% of deposit
        borrowAmount = bound(borrowAmount, 1, (depositAmount * 75) / 100);

        vm.prank(bob);
        pool.deposit(address(usdc), depositAmount * 2); // provide liquidity

        vm.prank(alice);
        pool.deposit(address(usdc), depositAmount);
        vm.prank(alice);
        pool.borrow(address(usdc), borrowAmount);

        assertEq(pool.getDebt(alice, address(usdc)), borrowAmount);
        assertGe(pool.healthFactor(alice), 1e18);
    }

    function testFuzz_repay_neverExceedsDebt(uint256 depositAmount, uint256 borrowAmount, uint256 repayAmount)
        public
    {
        depositAmount = bound(depositAmount, 1000e6, MAX_AMOUNT);
        borrowAmount = bound(borrowAmount, 1, (depositAmount * 75) / 100);
        repayAmount = bound(repayAmount, 1, depositAmount);

        vm.prank(bob);
        pool.deposit(address(usdc), depositAmount * 2);

        vm.prank(alice);
        pool.deposit(address(usdc), depositAmount);
        vm.prank(alice);
        pool.borrow(address(usdc), borrowAmount);

        vm.prank(alice);
        pool.repay(address(usdc), repayAmount);

        // Debt never goes negative
        assertGe(pool.getDebt(alice, address(usdc)), 0);
        // Debt is at most original borrow
        assertLe(pool.getDebt(alice, address(usdc)), borrowAmount);
    }

    function testFuzz_healthFactor_noDebtIsMax(uint256 amount) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        vm.prank(alice);
        pool.deposit(address(usdc), amount);
        assertEq(pool.healthFactor(alice), type(uint256).max);
    }

    function testFuzz_withdraw_afterFullRepay_succeeds(uint256 depositAmount, uint256 borrowAmount) public {
        depositAmount = bound(depositAmount, 1000e6, MAX_AMOUNT);
        borrowAmount = bound(borrowAmount, 1, (depositAmount * 75) / 100);

        vm.prank(bob);
        pool.deposit(address(usdc), depositAmount * 2);

        vm.prank(alice);
        pool.deposit(address(usdc), depositAmount);
        vm.prank(alice);
        pool.borrow(address(usdc), borrowAmount);

        vm.prank(alice);
        pool.repay(address(usdc), borrowAmount);

        vm.prank(alice);
        pool.withdraw(address(usdc), depositAmount);
        assertEq(pool.getCollateral(alice, address(usdc)), 0);
    }

    function testFuzz_totalBorrows_consistency(uint256 depositAmount, uint256 borrowAmount) public {
        depositAmount = bound(depositAmount, 1000e6, MAX_AMOUNT);
        borrowAmount = bound(borrowAmount, 1, (depositAmount * 75) / 100);

        vm.prank(bob);
        pool.deposit(address(usdc), depositAmount * 2);

        vm.prank(alice);
        pool.deposit(address(usdc), depositAmount);
        vm.prank(alice);
        pool.borrow(address(usdc), borrowAmount);

        assertEq(pool.totalBorrows(address(usdc)), borrowAmount);
    }

    function testFuzz_deposit_withdraw_noDebt(uint256 amount) public {
        amount = bound(amount, 1, MAX_AMOUNT);
        vm.prank(alice);
        pool.deposit(address(usdc), amount);
        vm.prank(alice);
        pool.withdraw(address(usdc), amount);
        assertEq(pool.getCollateral(alice, address(usdc)), 0);
        assertEq(usdc.balanceOf(alice), type(uint128).max);
    }

    function testFuzz_multipleUsers_totalDeposits(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 1, MAX_AMOUNT / 3);
        b = bound(b, 1, MAX_AMOUNT / 3);
        c = bound(c, 1, MAX_AMOUNT / 3);

        address charlie = makeAddr("charlie");
        usdc.mint(charlie, MAX_AMOUNT);
        vm.prank(charlie);
        usdc.approve(address(pool), type(uint256).max);

        vm.prank(alice);
        pool.deposit(address(usdc), a);
        vm.prank(bob);
        pool.deposit(address(usdc), b);
        vm.prank(charlie);
        pool.deposit(address(usdc), c);

        assertEq(pool.totalDeposits(address(usdc)), a + b + c);
    }

    function testFuzz_healthFactor_afterBorrow_isValid(uint256 depositAmount, uint256 borrowAmount) public {
        depositAmount = bound(depositAmount, 1000e6, MAX_AMOUNT);
        borrowAmount = bound(borrowAmount, 1, (depositAmount * 75) / 100);

        vm.prank(bob);
        pool.deposit(address(usdc), depositAmount * 2);

        vm.prank(alice);
        pool.deposit(address(usdc), depositAmount);
        vm.prank(alice);
        pool.borrow(address(usdc), borrowAmount);

        uint256 hf = pool.healthFactor(alice);
        assertGe(hf, 1e18); // must be safe
    }
}
