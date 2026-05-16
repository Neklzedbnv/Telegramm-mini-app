// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/LendingPool.sol";
import "../../src/mocks/MockERC20.sol";
import "../../src/mocks/MockOracle.sol";

/// @dev Handler contract for invariant testing
contract LendingHandler is Test {
    LendingPool public pool;
    MockERC20 public usdc;
    MockOracle public oracle;

    address[] public actors;
    uint256 public totalDeposited;
    uint256 public totalBorrowed;

    constructor(LendingPool _pool, MockERC20 _usdc, MockOracle _oracle) {
        pool = _pool;
        usdc = _usdc;
        oracle = _oracle;

        for (uint256 i = 0; i < 3; i++) {
            address actor = address(uint160(uint256(keccak256(abi.encodePacked("actor", i)))));
            actors.push(actor);
            usdc.mint(actor, 10_000_000e6);
            vm.prank(actor);
            usdc.approve(address(pool), type(uint256).max);
        }
    }

    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 1, 100_000e6);

        vm.prank(actor);
        pool.deposit(address(usdc), amount);
        totalDeposited += amount;
    }

    function borrow(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 collateral = pool.getCollateral(actor, address(usdc));
        if (collateral == 0) return;

        uint256 maxBorrow = (collateral * 75) / 100;
        uint256 currentDebt = pool.getDebt(actor, address(usdc));
        if (currentDebt >= maxBorrow) return;

        amount = bound(amount, 1, maxBorrow - currentDebt);

        uint256 available = pool.totalDeposits(address(usdc)) - pool.totalBorrows(address(usdc));
        if (available < amount) return;

        vm.prank(actor);
        try pool.borrow(address(usdc), amount) {
            totalBorrowed += amount;
        } catch {}
    }

    function repay(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 debt = pool.getDebt(actor, address(usdc));
        if (debt == 0) return;

        amount = bound(amount, 1, debt);

        vm.prank(actor);
        pool.repay(address(usdc), amount);
        totalBorrowed -= amount;
    }

    function withdraw(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 col = pool.getCollateral(actor, address(usdc));
        if (col == 0) return;

        amount = bound(amount, 1, col);

        vm.prank(actor);
        try pool.withdraw(address(usdc), amount) {
            totalDeposited -= amount;
        } catch {}
    }
}

contract LendingInvariantTest is Test {
    LendingPool pool;
    MockERC20 usdc;
    MockOracle oracle;
    LendingHandler handler;

    function setUp() public {
        oracle = new MockOracle();
        oracle.setPrice(address(0), 0);

        LendingPool impl = new LendingPool();
        bytes memory initData = abi.encodeCall(LendingPool.initialize, (address(oracle), address(this)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        pool = LendingPool(address(proxy));

        usdc = new MockERC20("USDC", "USDC", 6);
        oracle.setPrice(address(usdc), 1e30); // USDC 6 decimals: $1/token → 1e30
        pool.addSupportedToken(address(usdc));

        handler = new LendingHandler(pool, usdc, oracle);

        targetContract(address(handler));
    }

    /// @dev Invariant: totalBorrows <= totalDeposits (solvency)
    function invariant_totalBorrowsLessOrEqualDeposits() public view {
        assertLe(pool.totalBorrows(address(usdc)), pool.totalDeposits(address(usdc)));
    }

    /// @dev Invariant: contract token balance == totalDeposits - totalBorrows
    function invariant_contractBalanceMatchesAccounting() public view {
        uint256 balance = usdc.balanceOf(address(pool));
        uint256 expected = pool.totalDeposits(address(usdc)) - pool.totalBorrows(address(usdc));
        assertEq(balance, expected);
    }

    /// @dev Invariant: handler-tracked deposits match pool state
    function invariant_handlerTotalDepositsSynced() public view {
        assertEq(pool.totalDeposits(address(usdc)), handler.totalDeposited());
    }

    /// @dev Invariant: handler-tracked borrows match pool state
    function invariant_handlerTotalBorrowsSynced() public view {
        assertEq(pool.totalBorrows(address(usdc)), handler.totalBorrowed());
    }

    /// @dev Invariant: users with debt must have health factor >= 1 (since handler only borrows within LTV)
    function invariant_allBorrowersAreSolvent() public view {
        address[] memory actors = new address[](handler.actors(0) == address(0) ? 0 : 3);
        for (uint256 i = 0; i < 3; i++) {
            address actor = handler.actors(i);
            uint256 debt = pool.getDebt(actor, address(usdc));
            if (debt > 0) {
                uint256 hf = pool.healthFactor(actor);
                assertGe(hf, 1e18);
            }
        }
    }
}
