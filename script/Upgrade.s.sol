// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/core/LendingPoolV1.sol";
import "../contracts/core/LendingPoolV2.sol";

/// @title Upgrade
/// @notice Upgrades a deployed LendingPoolV1 proxy to LendingPoolV2
/// @dev Usage:
///      forge script script/Upgrade.s.sol \
///        --rpc-url $RPC_URL \
///        --broadcast \
///        --verify \
///        -e PRIVATE_KEY=... \
///        -e PROXY_ADDRESS=0x...
///
/// Required env vars:
///   PRIVATE_KEY    — owner's private key (must match proxy owner)
///   PROXY_ADDRESS  — address of the LendingPool ERC1967Proxy
///
/// Optional env vars:
///   FLASH_LOAN_FEE_BPS — fee in basis points for flash loans (default: 9 = 0.09%)
contract Upgrade is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address proxy = vm.envAddress("PROXY_ADDRESS");
        uint256 feeBps = vm.envOr("FLASH_LOAN_FEE_BPS", uint256(9));

        console2.log("Upgrading LendingPool at proxy:", proxy);
        console2.log("Deployer (owner):", deployer);
        console2.log("Flash loan fee (bps):", feeBps);

        vm.startBroadcast(deployerKey);

        // Deploy new V2 implementation
        LendingPoolV2 implV2 = new LendingPoolV2();
        console2.log("LendingPoolV2 impl deployed:", address(implV2));

        // Prepare V2 initialization data (sets flash loan fee)
        bytes memory initV2Data = abi.encodeCall(LendingPoolV2.initializeV2, (feeBps));

        // Execute upgrade — only the owner can call upgradeToAndCall
        LendingPoolV1(proxy).upgradeToAndCall(address(implV2), initV2Data);

        vm.stopBroadcast();

        // Verify upgrade
        LendingPoolV2 poolV2 = LendingPoolV2(proxy);
        string memory v = poolV2.version();
        console2.log("Upgrade successful. New version:", v);
        console2.log("Flash loan fee (bps):", poolV2.flashLoanFeeBps());

        require(keccak256(bytes(v)) == keccak256(bytes("2.0.0")), "version mismatch post-upgrade");
    }
}
