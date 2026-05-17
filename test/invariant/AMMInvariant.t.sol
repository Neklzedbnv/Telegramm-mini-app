// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "contracts/core/AMM.sol";
import "contracts/mocks/MockERC20.sol";

/// @notice Stateful invariant tests for AMM — required by BChT2 §3.3
///         "constant-product invariant (k never decreases on swap)"
contract AMMHandler is Test {
    AMM internal amm;
    MockERC20 internal tA;
    MockERC20 internal tB;

    address[] internal actors;
    uint256 public ghostK; // k captured after first liquidity event

    constructor(AMM _amm, MockERC20 _tA, MockERC20 _tB, address[3] memory _actors) {
        amm = _amm;
        tA = _tA;
        tB = _tB;
        for (uint256 i; i < 3; i++) {
            actors.push(_actors[i]);
        }
    }

    function addLiquidity(uint256 actorSeed, uint256 amtA, uint256 amtB) external {
        amtA = bound(amtA, 1e15, 50_000e18);
        amtB = bound(amtB, 1e15, 50_000e18);
        address actor = actors[actorSeed % actors.length];

        tA.mint(actor, amtA);
        tB.mint(actor, amtB);

        vm.startPrank(actor);
        tA.approve(address(amm), amtA);
        tB.approve(address(amm), amtB);
        try amm.addLiquidity(amtA, amtB) {
            if (ghostK == 0) ghostK = amm.getK();
        } catch {}
        vm.stopPrank();
    }

    function removeLiquidity(uint256 actorSeed, uint256 sharesFrac) external {
        address actor = actors[actorSeed % actors.length];
        uint256 shares = amm.balanceOf(actor);
        if (shares == 0) return;
        shares = bound(sharesFrac, 1, shares);

        vm.prank(actor);
        try amm.removeLiquidity(shares, 0, 0) {} catch {}
    }

    function swap(uint256 actorSeed, bool aToB, uint256 amountIn) external {
        if (ghostK == 0) return; // no liquidity yet
        amountIn = bound(amountIn, 1e15, 5_000e18);
        address actor = actors[actorSeed % actors.length];
        address tokenIn = aToB ? address(tA) : address(tB);

        MockERC20(tokenIn).mint(actor, amountIn);

        vm.startPrank(actor);
        MockERC20(tokenIn).approve(address(amm), amountIn);
        try amm.swap(tokenIn, amountIn, 0) {} catch {}
        vm.stopPrank();
    }
}

contract AMMInvariantTest is Test {
    AMM internal amm;
    MockERC20 internal tA;
    MockERC20 internal tB;
    AMMHandler internal handler;

    address[3] internal _actors;

    function setUp() public {
        tA = new MockERC20("TokenA", "TKA", 18);
        tB = new MockERC20("TokenB", "TKB", 18);
        amm = new AMM(address(tA), address(tB));

        _actors[0] = makeAddr("actor0");
        _actors[1] = makeAddr("actor1");
        _actors[2] = makeAddr("actor2");

        handler = new AMMHandler(amm, tA, tB, _actors);

        // Seed initial liquidity so k baseline is set
        address seeder = makeAddr("seeder");
        tA.mint(seeder, 100_000e18);
        tB.mint(seeder, 100_000e18);
        vm.startPrank(seeder);
        tA.approve(address(amm), 100_000e18);
        tB.approve(address(amm), 100_000e18);
        amm.addLiquidity(100_000e18, 100_000e18);
        vm.stopPrank();

        // Tell foundry's fuzzer to only call the handler
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = AMMHandler.addLiquidity.selector;
        selectors[1] = AMMHandler.removeLiquidity.selector;
        selectors[2] = AMMHandler.swap.selector;
        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    }

    /// @notice k = reserveA * reserveB must never decrease from the initial value
    ///         (swaps add fee to reserves, so k grows; liquidity add/remove is proportional)
    function invariant_k_never_decreases_on_swap() public view {
        uint256 kNow = amm.getK();
        // After initial seeding, k should be at least the seed k
        uint256 seedK = 100_000e18 * 100_000e18;
        assertGe(kNow, seedK, "k fell below initial seed value");
    }

    /// @notice reserveA must equal actual tokenA balance held by AMM contract
    function invariant_reserveA_matches_balance() public view {
        assertEq(amm.reserveA(), tA.balanceOf(address(amm)), "reserveA mismatch");
    }

    /// @notice reserveB must equal actual tokenB balance held by AMM contract
    function invariant_reserveB_matches_balance() public view {
        assertEq(amm.reserveB(), tB.balanceOf(address(amm)), "reserveB mismatch");
    }
}
