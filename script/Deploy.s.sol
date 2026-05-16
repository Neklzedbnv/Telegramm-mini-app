// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/LendingPool.sol";
import "../src/YieldVault.sol";
import "../src/mocks/MockOracle.sol";
import "../src/mocks/MockERC20.sol";

contract Deploy is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        vm.startBroadcast(deployer);

        // Deploy mock oracle (replace with Chainlink oracle for mainnet)
        MockOracle oracle = new MockOracle();

        // Deploy LendingPool implementation
        LendingPool impl = new LendingPool();

        // Deploy proxy
        bytes memory initData = abi.encodeCall(LendingPool.initialize, (address(oracle), deployer));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        LendingPool pool = LendingPool(address(proxy));

        // Deploy mock token
        MockERC20 usdc = new MockERC20("Mock USDC", "USDC", 6);
        oracle.setPrice(address(usdc), 1e18); // $1 per token (18 decimal precision)
        pool.addSupportedToken(address(usdc));

        // Deploy YieldVault
        YieldVault vault = new YieldVault(IERC20(address(usdc)), address(pool), deployer);

        vm.stopBroadcast();

        console.log("Oracle:      ", address(oracle));
        console.log("LendingPool: ", address(pool));
        console.log("YieldVault:  ", address(vault));
        console.log("USDC:        ", address(usdc));
    }
}
