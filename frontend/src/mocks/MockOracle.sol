// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IOracle.sol";

contract MockOracle is IOracle {
    mapping(address => uint256) public prices;

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function getPrice(address token) external view returns (uint256 price, uint256 updatedAt) {
        price = prices[token];
        updatedAt = block.timestamp;
    }
}
