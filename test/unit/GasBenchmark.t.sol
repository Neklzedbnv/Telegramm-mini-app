// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

/// @notice Isolated benchmarks comparing inline assembly vs pure Solidity
///         for the three assembly-optimized functions in the protocol.
///         Run with: forge test --match-contract GasBenchmarkTest --gas-report -vv
contract GasBenchmarkTest is Test {
    // ─── Health Factor Division ───────────────────────────────────────────────

    /// @dev Pure Solidity equivalent of _computeHealthFactor division
    function healthFactorSolidity(uint256 totalCollateralValue, uint256 totalDebtValue)
        public
        pure
        returns (uint256 hf)
    {
        uint256 weightedCollateral = (totalCollateralValue * 80) / 100;
        hf = (weightedCollateral * 1e18) / totalDebtValue;
    }

    /// @dev Inline assembly version (production code)
    function healthFactorAssembly(uint256 totalCollateralValue, uint256 totalDebtValue)
        public
        pure
        returns (uint256 hf)
    {
        uint256 PRECISION = 1e18;
        assembly {
            let weightedCollateral := div(mul(totalCollateralValue, 80), 100)
            hf := div(mul(weightedCollateral, PRECISION), totalDebtValue)
        }
    }

    function test_healthFactor_solidity() public pure {
        healthFactorSolidity(1000e18, 750e18);
    }

    function test_healthFactor_assembly() public pure {
        healthFactorAssembly(1000e18, 750e18);
    }

    // ─── WAD Normalization ────────────────────────────────────────────────────

    /// @dev Pure Solidity equivalent of OracleLib.normalizeToWad
    function normalizeToWadSolidity(int256 answer, uint8 decimals) public pure returns (uint256 result) {
        if (decimals < 18) {
            result = uint256(answer) * 10 ** (18 - decimals);
        } else {
            result = uint256(answer) / 10 ** (decimals - 18);
        }
    }

    /// @dev Inline assembly version (production code)
    function normalizeToWadAssembly(int256 answer, uint8 decimals) public pure returns (uint256 result) {
        assembly {
            switch lt(decimals, 18)
            case 1 { result := mul(answer, exp(10, sub(18, decimals))) }
            default { result := div(answer, exp(10, sub(decimals, 18))) }
        }
    }

    function test_normalizeToWad_solidity_8dec() public pure {
        normalizeToWadSolidity(100_000_000, 8); // $1.00 in 8-dec Chainlink feed
    }

    function test_normalizeToWad_assembly_8dec() public pure {
        normalizeToWadAssembly(100_000_000, 8);
    }

    function test_normalizeToWad_solidity_6dec() public pure {
        normalizeToWadSolidity(1_000_000, 6);
    }

    function test_normalizeToWad_assembly_6dec() public pure {
        normalizeToWadAssembly(1_000_000, 6);
    }

    // ─── CREATE2 Address Prediction ───────────────────────────────────────────

    /// @dev Pure Solidity equivalent
    function computeCreate2Solidity(bytes32 salt, bytes32 bytecodeHash, address deployer)
        public
        pure
        returns (address result)
    {
        result = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, bytecodeHash)))));
    }

    /// @dev Inline assembly version (production code)
    /// address must be left-shifted 96 bits so it occupies bytes 1-20 in the 32-byte word
    function computeCreate2Assembly(bytes32 salt, bytes32 bytecodeHash, address deployer)
        public
        pure
        returns (address result)
    {
        assembly {
            let ptr := mload(0x40)
            mstore8(ptr, 0xff)
            mstore(add(ptr, 1), shl(96, deployer))
            mstore(add(ptr, 21), salt)
            mstore(add(ptr, 53), bytecodeHash)
            result := and(keccak256(ptr, 85), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    function test_create2_solidity() public pure {
        computeCreate2Solidity(bytes32(uint256(1)), keccak256("init"), address(0xBEEF));
    }

    function test_create2_assembly() public pure {
        computeCreate2Assembly(bytes32(uint256(1)), keccak256("init"), address(0xBEEF));
    }

    // ─── Correctness check (assembly == solidity) ─────────────────────────────

    function testFuzz_healthFactor_equivalence(uint128 col, uint128 debt) public pure {
        vm.assume(debt > 0);
        assertEq(healthFactorSolidity(col, debt), healthFactorAssembly(col, debt));
    }

    function testFuzz_normalizeToWad_equivalence(int64 answer, uint8 decimals) public pure {
        vm.assume(answer > 0 && decimals <= 18);
        assertEq(normalizeToWadSolidity(answer, decimals), normalizeToWadAssembly(answer, decimals));
    }

    function testFuzz_create2_equivalence(bytes32 salt, bytes32 hash) public pure {
        address deployer = address(0xCAFE);
        assertEq(computeCreate2Solidity(salt, hash, deployer), computeCreate2Assembly(salt, hash, deployer));
    }
}
