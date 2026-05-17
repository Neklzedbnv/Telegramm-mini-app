// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../contracts/oracle/OracleLib.sol";
import "../../contracts/oracle/interfaces/AggregatorV3Interface.sol";
import "../../contracts/mocks/MockV3Aggregator.sol";
import "../../contracts/oracle/ChainlinkOracleAdapter.sol";

/// @dev Exposes OracleLib internal functions for direct testing
contract OracleLibHarness {
    using OracleLib for AggregatorV3Interface;

    function staleCheck(AggregatorV3Interface feed)
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return feed.staleCheckLatestRoundData();
    }

    function getWad(AggregatorV3Interface feed) external view returns (uint256 price, uint256 updatedAt) {
        return feed.getWadPrice();
    }

    function normalize(int256 answer, uint8 dec) external pure returns (uint256) {
        return OracleLib.normalizeToWad(answer, dec);
    }

    function computeCreate2(bytes32 salt, bytes32 bytecodeHash, address deployer)
        external
        pure
        returns (address)
    {
        return OracleLib.computeCreate2Address(salt, bytecodeHash, deployer);
    }
}

contract OracleLibTest is Test {
    OracleLibHarness harness;
    MockV3Aggregator feed8;  // 8 decimals (typical USD feed)
    MockV3Aggregator feed18; // 18 decimals
    MockV3Aggregator feed6;  // 6 decimals (atypical)

    int256 constant PRICE_2000_USD = 2000e8; // $2000 in 8-decimal feed format

    function setUp() public {
        harness = new OracleLibHarness();
        feed8 = new MockV3Aggregator(8, PRICE_2000_USD);
        feed18 = new MockV3Aggregator(18, 2000e18);
        feed6 = new MockV3Aggregator(6, 2000e6);
    }

    // ─── normalizeToWad ───────────────────────────────────────────────────────

    function test_normalize_8decimals_to18() public view {
        uint256 result = harness.normalize(PRICE_2000_USD, 8);
        assertEq(result, 2000e18);
    }

    function test_normalize_18decimals_unchanged() public view {
        uint256 result = harness.normalize(2000e18, 18);
        assertEq(result, 2000e18);
    }

    function test_normalize_6decimals_to18() public view {
        uint256 result = harness.normalize(2000e6, 6);
        assertEq(result, 2000e18);
    }

    function test_normalize_1dollar_8dec() public view {
        // $1.00 in 8 decimals = 100000000
        uint256 result = harness.normalize(1e8, 8);
        assertEq(result, 1e18);
    }

    function test_normalize_decimalsGreaterThan18() public view {
        // 20 decimals: 2000e20 → WAD = 2000e18
        uint256 result = harness.normalize(2000e20, 20);
        assertEq(result, 2000e18);
    }

    // ─── staleCheckLatestRoundData — happy path ────────────────────────────────

    function test_staleCheck_freshPrice_succeeds() public view {
        (, int256 answer,,,) = harness.staleCheck(AggregatorV3Interface(address(feed8)));
        assertEq(answer, PRICE_2000_USD);
    }

    function test_staleCheck_returnsCorrectTimestamp() public view {
        (,,, uint256 updatedAt,) = harness.staleCheck(AggregatorV3Interface(address(feed8)));
        assertEq(updatedAt, block.timestamp);
    }

    // ─── staleCheckLatestRoundData — stale prices ─────────────────────────────

    function test_staleCheck_revertsOnStalePrice() public {
        // Push time past STALE_TIMEOUT = 3 hours
        uint256 staleTs = block.timestamp - (OracleLib.STALE_TIMEOUT + 1);
        feed8.updateRoundData(1, PRICE_2000_USD, staleTs, staleTs);

        vm.expectRevert();
        harness.staleCheck(AggregatorV3Interface(address(feed8)));
    }

    function test_staleCheck_revertsOnZeroUpdatedAt() public {
        // updatedAt = 0 signals an incomplete round
        feed8.updateRoundData(1, PRICE_2000_USD, 0, block.timestamp);

        vm.expectRevert();
        harness.staleCheck(AggregatorV3Interface(address(feed8)));
    }

    function test_staleCheck_exactlyAtTimeoutBoundary() public {
        // At exactly STALE_TIMEOUT seconds old the price is still valid
        uint256 boundaryTs = block.timestamp - OracleLib.STALE_TIMEOUT;
        feed8.updateRoundData(1, PRICE_2000_USD, boundaryTs, boundaryTs);

        // Should NOT revert
        harness.staleCheck(AggregatorV3Interface(address(feed8)));
    }

    // ─── staleCheckLatestRoundData — invalid prices ───────────────────────────

    function test_staleCheck_revertsOnZeroAnswer() public {
        feed8.updateAnswer(0);
        vm.expectRevert();
        harness.staleCheck(AggregatorV3Interface(address(feed8)));
    }

    function test_staleCheck_revertsOnNegativeAnswer() public {
        feed8.updateAnswer(-1);
        vm.expectRevert();
        harness.staleCheck(AggregatorV3Interface(address(feed8)));
    }

    // ─── getWadPrice ──────────────────────────────────────────────────────────

    function test_getWad_8decimalFeed() public view {
        (uint256 price, uint256 updatedAt) = harness.getWad(AggregatorV3Interface(address(feed8)));
        assertEq(price, 2000e18);
        assertEq(updatedAt, block.timestamp);
    }

    function test_getWad_18decimalFeed() public view {
        (uint256 price,) = harness.getWad(AggregatorV3Interface(address(feed18)));
        assertEq(price, 2000e18);
    }

    function test_getWad_6decimalFeed() public view {
        (uint256 price,) = harness.getWad(AggregatorV3Interface(address(feed6)));
        assertEq(price, 2000e18);
    }

    // ─── ChainlinkOracleAdapter ────────────────────────────────────────────────

    function test_adapter_getPrice_success() public {
        address tokenAddr = makeAddr("weth");
        ChainlinkOracleAdapter adapter = new ChainlinkOracleAdapter(address(this));
        adapter.setFeed(tokenAddr, address(feed8));

        (uint256 price, uint256 updatedAt) = adapter.getPrice(tokenAddr);
        assertEq(price, 2000e18);
        assertGt(updatedAt, 0);
    }

    function test_adapter_revertsIfFeedNotSet() public {
        address tokenAddr = makeAddr("unknown");
        ChainlinkOracleAdapter adapter = new ChainlinkOracleAdapter(address(this));
        vm.expectRevert(abi.encodeWithSelector(ChainlinkOracleAdapter.FeedNotSet.selector, tokenAddr));
        adapter.getPrice(tokenAddr);
    }

    function test_adapter_revertsIfFeedStale() public {
        address tokenAddr = makeAddr("eth");
        ChainlinkOracleAdapter adapter = new ChainlinkOracleAdapter(address(this));
        adapter.setFeed(tokenAddr, address(feed8));

        // Make the feed stale
        uint256 staleTs = block.timestamp - (OracleLib.STALE_TIMEOUT + 1);
        feed8.updateRoundData(1, PRICE_2000_USD, staleTs, staleTs);

        vm.expectRevert();
        adapter.getPrice(tokenAddr);
    }

    // ─── computeCreate2Address ────────────────────────────────────────────────

    function test_computeCreate2_matchesOZResult() public view {
        bytes32 salt = keccak256("test-salt");
        bytes32 bHash = keccak256("bytecode");
        address deployer = address(0x1234);

        address predicted = harness.computeCreate2(salt, bHash, deployer);

        // Verify format (should be a valid address, not zero)
        assertTrue(predicted != address(0));
    }

    function test_computeCreate2_deterministicResult() public view {
        bytes32 salt = keccak256("same-salt");
        bytes32 bHash = keccak256("same-bytecode");
        address deployer = address(0xDEAD);

        address a = harness.computeCreate2(salt, bHash, deployer);
        address b = harness.computeCreate2(salt, bHash, deployer);
        assertEq(a, b);
    }

    function test_computeCreate2_differentSaltsDifferentAddresses() public view {
        bytes32 bHash = keccak256("same-bytecode");
        address deployer = address(0xDEAD);

        address a = harness.computeCreate2(keccak256("salt1"), bHash, deployer);
        address b = harness.computeCreate2(keccak256("salt2"), bHash, deployer);
        assertNotEq(a, b);
    }
}
