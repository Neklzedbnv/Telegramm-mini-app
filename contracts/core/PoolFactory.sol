// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LendingPoolV1} from "./LendingPoolV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OracleLib} from "../oracle/OracleLib.sol";

/// @title PoolFactory
/// @notice Deploys LendingPoolV1 proxies using both CREATE and CREATE2 (deterministic)
/// @dev Factory pattern benefits:
///      • Tracks all deployed pools in a single registry
///      • CREATE2 allows pre-computing addresses before deployment
///      • A single canonical implementation reduces deployment cost per pool
///
/// Address prediction:
///   predictAddress(oracle, owner, salt) returns the address a pool WILL have if deployed
///   with deployPoolDeterministic(oracle, owner, salt) — uses CREATE2 under the hood.
contract PoolFactory is Ownable {
    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice The shared LendingPoolV1 implementation (deployed once)
    address public immutable implementation;

    /// @notice All pools deployed by this factory, in order
    address[] public allPools;

    /// @notice Maps a pool address to true if deployed by this factory
    mapping(address => bool) public isDeployedPool;

    // ─── Events ───────────────────────────────────────────────────────────────

    event PoolDeployed(address indexed pool, address indexed oracle, address indexed poolOwner, bytes32 salt);
    event PoolDeployedDeterministic(
        address indexed pool, address indexed oracle, address indexed poolOwner, bytes32 salt
    );

    // ─── Errors ───────────────────────────────────────────────────────────────

    error ZeroAddress();
    error SaltAlreadyUsed(bytes32 salt);

    // ─── Tracking ─────────────────────────────────────────────────────────────

    /// @dev salt → deployed address (zero if unused)
    mapping(bytes32 => address) public saltToPool;

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @param initialOwner Factory owner (can be changed later)
    constructor(address initialOwner) Ownable(initialOwner) {
        // Deploy a single canonical implementation
        LendingPoolV1 impl = new LendingPoolV1();
        implementation = address(impl);
    }

    // ─── CREATE Deployment ────────────────────────────────────────────────────

    /// @notice Deploy a new LendingPoolV1 proxy using regular CREATE (non-deterministic)
    /// @param oracle    IOracle address for the new pool
    /// @param poolOwner Owner of the new pool (receives admin rights)
    /// @return pool     The address of the deployed proxy
    function deployPool(address oracle, address poolOwner) external returns (address pool) {
        if (oracle == address(0) || poolOwner == address(0)) revert ZeroAddress();

        bytes memory initData = abi.encodeCall(LendingPoolV1.initialize, (oracle, poolOwner));
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, initData);
        pool = address(proxy);

        _registerPool(pool);

        emit PoolDeployed(pool, oracle, poolOwner, bytes32(0));
    }

    // ─── CREATE2 Deterministic Deployment ─────────────────────────────────────

    /// @notice Deploy a new LendingPoolV1 proxy using CREATE2 (deterministic address)
    /// @param oracle    IOracle address for the new pool
    /// @param poolOwner Owner of the new pool
    /// @param salt      32-byte unique salt; reverts if already used by this factory
    /// @return pool     The deterministic address of the deployed proxy
    function deployPoolDeterministic(address oracle, address poolOwner, bytes32 salt)
        external
        returns (address pool)
    {
        if (oracle == address(0) || poolOwner == address(0)) revert ZeroAddress();
        if (saltToPool[salt] != address(0)) revert SaltAlreadyUsed(salt);

        bytes memory initData = abi.encodeCall(LendingPoolV1.initialize, (oracle, poolOwner));

        // Solidity's `new T{salt: s}(...)` syntax compiles to CREATE2
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(implementation, initData);
        pool = address(proxy);

        saltToPool[salt] = pool;
        _registerPool(pool);

        emit PoolDeployedDeterministic(pool, oracle, poolOwner, salt);
    }

    // ─── Address Prediction ───────────────────────────────────────────────────

    /// @notice Predict the address of a pool before it is deployed
    /// @dev Must use the SAME oracle, poolOwner, and salt as the actual deployment call.
    ///      Returns address(0) if the salt is already used (pool already deployed).
    /// @param oracle    The oracle address that will be passed to initialize()
    /// @param poolOwner The owner that will be passed to initialize()
    /// @param salt      The CREATE2 salt
    /// @return predicted The deterministic future address
    function predictAddress(address oracle, address poolOwner, bytes32 salt)
        external
        view
        returns (address predicted)
    {
        bytes memory initData = abi.encodeCall(LendingPoolV1.initialize, (oracle, poolOwner));
        bytes memory proxyBytecode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initData));
        bytes32 bytecodeHash = keccak256(proxyBytecode);

        // Use OracleLib's assembly-optimized CREATE2 address computation
        predicted = OracleLib.computeCreate2Address(salt, bytecodeHash, address(this));
    }

    /// @notice Pure assembly-based address prediction (for gas benchmarking comparison)
    /// @dev Identical to predictAddress() but uses inline assembly directly rather than OracleLib
    function predictAddressAssembly(bytes32 salt, bytes32 bytecodeHash) external view returns (address predicted) {
        assembly {
            // Allocate scratch space at the free memory pointer
            let ptr := mload(0x40)
            // Layout: 0xff | deployer(20) | salt(32) | bytecodeHash(32) = 85 bytes
            mstore8(ptr, 0xff)
            mstore(add(ptr, 0x01), shl(96, address()))
            mstore(add(ptr, 0x15), salt)
            mstore(add(ptr, 0x35), bytecodeHash)
            predicted := and(keccak256(ptr, 0x55), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    // ─── Registry ─────────────────────────────────────────────────────────────

    /// @notice Returns all pools deployed by this factory
    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }

    /// @notice Returns the total number of pools deployed
    function poolCount() external view returns (uint256) {
        return allPools.length;
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    function _registerPool(address pool) internal {
        allPools.push(pool);
        isDeployedPool[pool] = true;
    }
}
