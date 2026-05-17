// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/core/LendingPoolV1.sol";
import "../contracts/core/PoolFactory.sol";
import "../contracts/vault/YieldVault.sol";
import "../contracts/governance/DeFiToken.sol";
import "../contracts/governance/DeFiTimelock.sol";
import "../contracts/governance/DeFiGovernor.sol";
import "../contracts/tokens/PositionNFT.sol";
import "../contracts/oracle/ChainlinkOracleAdapter.sol";
import "../contracts/mocks/MockOracle.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/core/AMM.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title Deploy
/// @notice Full protocol deployment script for Arbitrum Sepolia (or local Anvil fork)
/// @dev Usage:
///      Local:   forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
///      Testnet: forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
///
/// Required env vars:
///   PRIVATE_KEY        — deployer private key
///   RPC_URL            — target network RPC
///   ETHERSCAN_API_KEY  — Arbiscan API key (for --verify)
///
/// Optional env vars:
///   USE_MOCK_ORACLE    — set to "true" to deploy MockOracle (default for local/testnet)
///   INITIAL_TOKEN_SUPPLY — DeFiToken initial supply (default: 10_000_000e18)
contract Deploy is Script {
    address public oracle;
    address public lendingPoolImpl;
    address public lendingPool;
    address public factory;
    address public vault;
    address public governanceToken;
    address public timelockAddr;
    address public governorAddr;
    address public positionNFTAddr;
    address public usdc;
    address public tokenA;
    address public tokenB;
    address public ammAddr;

    uint256 constant DEFAULT_INITIAL_SUPPLY = 10_000_000e18;
    uint256 constant USDC_MOCK_PRICE = 1e30; // $1 for 6-decimal USDC

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        bool useMockOracle = _strEq(vm.envOr("USE_MOCK_ORACLE", string("true")), "true");
        uint256 initialSupply = vm.envOr("INITIAL_TOKEN_SUPPLY", DEFAULT_INITIAL_SUPPLY);

        vm.startBroadcast(deployerKey);

        // 1. Oracle
        if (useMockOracle) {
            MockOracle mockOracle = new MockOracle();
            oracle = address(mockOracle);
            console2.log("MockOracle:              ", oracle);
        } else {
            ChainlinkOracleAdapter chainlinkAdapter = new ChainlinkOracleAdapter(deployer);
            oracle = address(chainlinkAdapter);
            console2.log("ChainlinkOracleAdapter:  ", oracle);
        }

        // 2. LendingPoolV1 Implementation + Proxy
        lendingPoolImpl = address(new LendingPoolV1());
        bytes memory initData = abi.encodeCall(LendingPoolV1.initialize, (oracle, deployer));
        lendingPool = address(new ERC1967Proxy(lendingPoolImpl, initData));

        console2.log("LendingPoolV1 impl:      ", lendingPoolImpl);
        console2.log("LendingPool proxy:       ", lendingPool);

        // 3. PoolFactory
        factory = address(new PoolFactory(deployer));
        console2.log("PoolFactory:             ", factory);

        // 4. Governance Token
        governanceToken = address(new DeFiToken(deployer, initialSupply));
        console2.log("DeFiToken (DGT):         ", governanceToken);

        // 5. Timelock + Governor
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // anyone can execute after delay
        DeFiTimelock timelock = new DeFiTimelock(2 days, proposers, executors, deployer);
        timelockAddr = address(timelock);
        console2.log("DeFiTimelock:            ", timelockAddr);

        DeFiGovernor gov = new DeFiGovernor(IVotes(governanceToken), timelock);
        governorAddr = address(gov);
        console2.log("DeFiGovernor:            ", governorAddr);

        // Wire: governor gets proposer + canceller; renounce deployer admin
        timelock.grantRole(timelock.PROPOSER_ROLE(), governorAddr);
        timelock.grantRole(timelock.CANCELLER_ROLE(), governorAddr);
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        // Transfer protocol ownership to Timelock so governance controls it
        LendingPoolV1(lendingPool).transferOwnership(timelockAddr);
        DeFiToken(governanceToken).transferOwnership(timelockAddr);

        // 6. PositionNFT (owner = LendingPool proxy)
        PositionNFT nft = new PositionNFT(lendingPool);
        positionNFTAddr = address(nft);
        console2.log("PositionNFT:             ", positionNFTAddr);
        // Note: setPositionNFT must be called via governance after timelock owns the pool

        // 7. Mock USDC (for testnet / local only)
        if (useMockOracle) {
            MockERC20 mockUsdc = new MockERC20("USD Coin", "USDC", 6);
            usdc = address(mockUsdc);
            console2.log("MockUSDC:                ", usdc);

            MockOracle(oracle).setPrice(usdc, USDC_MOCK_PRICE);
            LendingPoolV1(lendingPool).addSupportedToken(usdc);
            mockUsdc.mint(deployer, 1_000_000e6);

            // 8. YieldVault
            vault = address(new YieldVault(IERC20(usdc), lendingPool, deployer));
            console2.log("YieldVault:              ", vault);

            // 9. AMM — two mock ERC20 tokens + seed liquidity
            MockERC20 tA = new MockERC20("Mock TokenA", "TKNA", 18);
            MockERC20 tB = new MockERC20("Mock TokenB", "TKNB", 18);
            tokenA = address(tA);
            tokenB = address(tB);
            console2.log("AMM TokenA:              ", tokenA);
            console2.log("AMM TokenB:              ", tokenB);

            AMM amm = new AMM(tokenA, tokenB);
            ammAddr = address(amm);
            console2.log("AMM:                     ", ammAddr);

            // Seed initial liquidity so the pool is usable immediately
            uint256 seedAmount = 100_000e18;
            tA.mint(deployer, seedAmount);
            tB.mint(deployer, seedAmount);
            tA.approve(ammAddr, seedAmount);
            tB.approve(ammAddr, seedAmount);
            amm.addLiquidity(seedAmount, seedAmount);
            console2.log("AMM seeded with 100k TKNA / 100k TKNB");
        }

        vm.stopBroadcast();

        console2.log("\n=== DEPLOYMENT COMPLETE ===");
        console2.log("Network:", block.chainid);
        console2.log("Deployer:", deployer);
    }

    function _strEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
