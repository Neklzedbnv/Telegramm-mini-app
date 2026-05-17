// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/core/PoolFactory.sol";

/// @title RedeployFactory
/// @notice Redeploys PoolFactory only (standalone, no other protocol changes).
///         Use when PoolFactory bytecode is stale due to changes in LendingPoolV1
///         (the factory embeds LendingPoolV1 creation code in its constructor).
///
/// Usage:
///   forge script script/RedeployFactory.s.sol \
///     --rpc-url $RPC_URL \
///     --broadcast \
///     --verify \
///     --etherscan-api-key $ETHERSCAN_API_KEY \
///     -vvv
contract RedeployFactory is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        PoolFactory factory = new PoolFactory(deployer);

        vm.stopBroadcast();

        console2.log("PoolFactory (new):", address(factory));
        console2.log("Owner:            ", deployer);
        console2.log("Implementation:   ", factory.implementation());
        console2.log("\nUpdate README.md with the new PoolFactory address above.");
    }
}
