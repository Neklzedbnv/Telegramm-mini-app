// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

/// @title Verify
/// @notice Helper script that prints forge verify-contract commands for all deployed contracts
/// @dev Run this after Deploy.s.sol to get copy-paste verification commands.
///      Actual verification happens via forge verify-contract, not this script.
///
/// Usage:
///   forge script script/Verify.s.sol \
///     -e CHAIN_ID=421614 \
///     -e ETHERSCAN_API_KEY=$ARBISCAN_KEY \
///     -e LENDING_POOL_IMPL=0x... \
///     -e LENDING_POOL_PROXY=0x... \
///     -e FACTORY=0x... \
///     -e VAULT=0x... \
///     -e GOVERNANCE_TOKEN=0x... \
///     -e ORACLE=0x...
contract Verify is Script {
    function run() external view {
        uint256 chainId = vm.envOr("CHAIN_ID", uint256(421614)); // Arbitrum Sepolia
        string memory apiKey = vm.envOr("ETHERSCAN_API_KEY", string(""));

        address impl = vm.envOr("LENDING_POOL_IMPL", address(0));
        address proxy = vm.envOr("LENDING_POOL_PROXY", address(0));
        address factory = vm.envOr("FACTORY", address(0));
        address vault = vm.envOr("VAULT", address(0));
        address govToken = vm.envOr("GOVERNANCE_TOKEN", address(0));
        address oracle = vm.envOr("ORACLE", address(0));

        console2.log("\n=== VERIFICATION COMMANDS ===\n");
        console2.log("Chain ID:", chainId);
        console2.log("(Run each command after setting ETHERSCAN_API_KEY in your shell)\n");

        if (impl != address(0)) {
            console2.log("# LendingPoolV1 Implementation");
            console2.log(
                string.concat(
                    "forge verify-contract ",
                    vm.toString(impl),
                    " contracts/core/LendingPoolV1.sol:LendingPoolV1",
                    " --chain-id ",
                    vm.toString(chainId),
                    " --etherscan-api-key ",
                    apiKey
                )
            );
        }

        if (proxy != address(0)) {
            console2.log("\n# LendingPool Proxy");
            console2.log(
                string.concat(
                    "forge verify-contract ",
                    vm.toString(proxy),
                    " lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy",
                    " --chain-id ",
                    vm.toString(chainId),
                    " --etherscan-api-key ",
                    apiKey
                )
            );
        }

        if (factory != address(0)) {
            console2.log("\n# PoolFactory");
            console2.log(
                string.concat(
                    "forge verify-contract ",
                    vm.toString(factory),
                    " contracts/core/PoolFactory.sol:PoolFactory",
                    " --chain-id ",
                    vm.toString(chainId),
                    " --etherscan-api-key ",
                    apiKey
                )
            );
        }

        if (vault != address(0)) {
            console2.log("\n# YieldVault");
            console2.log(
                string.concat(
                    "forge verify-contract ",
                    vm.toString(vault),
                    " contracts/vault/YieldVault.sol:YieldVault",
                    " --chain-id ",
                    vm.toString(chainId),
                    " --etherscan-api-key ",
                    apiKey
                )
            );
        }

        if (govToken != address(0)) {
            console2.log("\n# DeFiToken");
            console2.log(
                string.concat(
                    "forge verify-contract ",
                    vm.toString(govToken),
                    " contracts/governance/DeFiToken.sol:DeFiToken",
                    " --chain-id ",
                    vm.toString(chainId),
                    " --etherscan-api-key ",
                    apiKey
                )
            );
        }

        if (oracle != address(0)) {
            console2.log("\n# ChainlinkOracleAdapter");
            console2.log(
                string.concat(
                    "forge verify-contract ",
                    vm.toString(oracle),
                    " contracts/oracle/ChainlinkOracleAdapter.sol:ChainlinkOracleAdapter",
                    " --chain-id ",
                    vm.toString(chainId),
                    " --etherscan-api-key ",
                    apiKey
                )
            );
        }

        console2.log("\n=== END VERIFICATION COMMANDS ===\n");
    }
}
