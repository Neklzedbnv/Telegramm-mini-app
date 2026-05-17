// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/core/PoolFactory.sol";
import "../../contracts/core/LendingPoolV1.sol";
import "../../contracts/mocks/MockOracle.sol";

contract PoolFactoryTest is Test {
    PoolFactory factory;
    MockOracle oracle;

    address owner = makeAddr("owner");
    address poolOwner = makeAddr("poolOwner");
    address alice = makeAddr("alice");

    function setUp() public {
        vm.prank(owner);
        factory = new PoolFactory(owner);
        oracle = new MockOracle();
    }

    // ─── Constructor ──────────────────────────────────────────────────────────

    function test_implementation_isDeployed() public view {
        assertTrue(factory.implementation() != address(0));
    }

    function test_owner_isCorrect() public view {
        assertEq(factory.owner(), owner);
    }

    function test_initialPoolCount_isZero() public view {
        assertEq(factory.poolCount(), 0);
    }

    // ─── deployPool (CREATE) ──────────────────────────────────────────────────

    function test_deployPool_succeeds() public {
        address pool = factory.deployPool(address(oracle), poolOwner);
        assertTrue(pool != address(0));
    }

    function test_deployPool_isRegistered() public {
        address pool = factory.deployPool(address(oracle), poolOwner);
        assertTrue(factory.isDeployedPool(pool));
    }

    function test_deployPool_incrementsCount() public {
        factory.deployPool(address(oracle), poolOwner);
        assertEq(factory.poolCount(), 1);
        factory.deployPool(address(oracle), poolOwner);
        assertEq(factory.poolCount(), 2);
    }

    function test_deployPool_poolIsInitialized() public {
        address pool = factory.deployPool(address(oracle), poolOwner);
        LendingPoolV1 lp = LendingPoolV1(pool);
        assertEq(lp.version(), "1.0.0");
        assertEq(lp.owner(), poolOwner);
        assertEq(address(lp.oracle()), address(oracle));
    }

    function test_deployPool_emitsEvent() public {
        vm.expectEmit(false, true, true, false);
        emit PoolFactory.PoolDeployed(address(0), address(oracle), poolOwner, bytes32(0));
        factory.deployPool(address(oracle), poolOwner);
    }

    function test_deployPool_revertsZeroOracle() public {
        vm.expectRevert(PoolFactory.ZeroAddress.selector);
        factory.deployPool(address(0), poolOwner);
    }

    function test_deployPool_revertsZeroOwner() public {
        vm.expectRevert(PoolFactory.ZeroAddress.selector);
        factory.deployPool(address(oracle), address(0));
    }

    function test_deployPool_multiplePoolsInAllPools() public {
        factory.deployPool(address(oracle), poolOwner);
        factory.deployPool(address(oracle), poolOwner);
        address[] memory pools = factory.getAllPools();
        assertEq(pools.length, 2);
    }

    // ─── deployPoolDeterministic (CREATE2) ────────────────────────────────────

    function test_deployPoolDeterministic_succeeds() public {
        bytes32 salt = keccak256("test-pool");
        address pool = factory.deployPoolDeterministic(address(oracle), poolOwner, salt);
        assertTrue(pool != address(0));
    }

    function test_deployPoolDeterministic_isRegistered() public {
        bytes32 salt = keccak256("registered-pool");
        address pool = factory.deployPoolDeterministic(address(oracle), poolOwner, salt);
        assertTrue(factory.isDeployedPool(pool));
    }

    function test_deployPoolDeterministic_saltToPoolMapping() public {
        bytes32 salt = keccak256("salt-tracking");
        address pool = factory.deployPoolDeterministic(address(oracle), poolOwner, salt);
        assertEq(factory.saltToPool(salt), pool);
    }

    function test_deployPoolDeterministic_revertsOnReusingsSalt() public {
        bytes32 salt = keccak256("reused-salt");
        factory.deployPoolDeterministic(address(oracle), poolOwner, salt);
        vm.expectRevert(abi.encodeWithSelector(PoolFactory.SaltAlreadyUsed.selector, salt));
        factory.deployPoolDeterministic(address(oracle), poolOwner, salt);
    }

    function test_deployPoolDeterministic_emitsEvent() public {
        bytes32 salt = keccak256("event-salt");
        vm.expectEmit(false, true, true, true);
        emit PoolFactory.PoolDeployedDeterministic(address(0), address(oracle), poolOwner, salt);
        factory.deployPoolDeterministic(address(oracle), poolOwner, salt);
    }

    // ─── predictAddress ────────────────────────────────────────────────────────

    function test_predictAddress_matchesActualDeployment() public {
        bytes32 salt = keccak256("predict-test");
        address predicted = factory.predictAddress(address(oracle), poolOwner, salt);
        address actual = factory.deployPoolDeterministic(address(oracle), poolOwner, salt);
        assertEq(predicted, actual);
    }

    function test_predictAddress_differentSaltsDifferentAddresses() public view {
        bytes32 salt1 = keccak256("salt-a");
        bytes32 salt2 = keccak256("salt-b");
        address a = factory.predictAddress(address(oracle), poolOwner, salt1);
        address b = factory.predictAddress(address(oracle), poolOwner, salt2);
        assertNotEq(a, b);
    }

    function test_predictAddressAssembly_matchesSolidity() public view {
        bytes32 salt = keccak256("assembly-predict");
        // Compute bytecode hash matching factory.predictAddress logic
        bytes memory initData = abi.encodeCall(LendingPoolV1.initialize, (address(oracle), poolOwner));
        bytes memory proxyBytecode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(factory.implementation(), initData));
        bytes32 bytecodeHash = keccak256(proxyBytecode);

        address solidity = factory.predictAddress(address(oracle), poolOwner, salt);
        address assembly_ = factory.predictAddressAssembly(salt, bytecodeHash);
        assertEq(solidity, assembly_);
    }

    // ─── getAllPools ───────────────────────────────────────────────────────────

    function test_getAllPools_emptyByDefault() public view {
        assertEq(factory.getAllPools().length, 0);
    }

    function test_getAllPools_containsCorrectAddresses() public {
        address p1 = factory.deployPool(address(oracle), poolOwner);
        bytes32 salt = keccak256("get-all");
        address p2 = factory.deployPoolDeterministic(address(oracle), poolOwner, salt);
        address[] memory pools = factory.getAllPools();
        assertEq(pools[0], p1);
        assertEq(pools[1], p2);
    }
}
