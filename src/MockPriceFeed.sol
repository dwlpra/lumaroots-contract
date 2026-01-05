// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * MockPriceFeed
 *
 * Simple mock oracle for USD/MNT price. For testnet we just use 1:1 rate.
 * In production you'd use Chainlink or Pyth.
 *
 * The frontend handles EUR→USD conversion (Tree-Nation prices are in EUR).
 * This contract only deals with USD→MNT for the actual blockchain payment.
 */
contract MockPriceFeed is Ownable {
    // Price with 8 decimals (Chainlink standard)
    // 1_00000000 = 1 USD = 1 MNT
    int256 private _price;
    uint8 private constant DECIMALS = 8;
    
    uint256 private _updatedAt;
    
    string public description = "USD / MNT";
    
    event PriceUpdated(int256 oldPrice, int256 newPrice, uint256 timestamp);
    
    constructor(int256 initialPrice) Ownable(msg.sender) {
        require(initialPrice > 0, "Price must be positive");
        _price = initialPrice;
        _updatedAt = block.timestamp;
    }
    
    // ============ Chainlink-compatible Interface ============
    
    // Returns latest price data (Chainlink AggregatorV3Interface style)
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (1, _price, _updatedAt, _updatedAt, 1);
    }
    
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }
    
    function latestAnswer() external view returns (int256) {
        return _price;
    }
    
    // ============ Admin ============
    
    function updatePrice(int256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be positive");
        int256 oldPrice = _price;
        _price = newPrice;
        _updatedAt = block.timestamp;
        emit PriceUpdated(oldPrice, newPrice, block.timestamp);
    }
    
    // ============ Helpers ============
    
    // Convert USD to MNT (both in 18 decimals/wei)
    function usdToMnt(uint256 usdAmount) external view returns (uint256) {
        require(_price > 0, "Invalid price");
        return (usdAmount * uint256(_price)) / (10 ** DECIMALS);
    }
    
    // Convert MNT to USD (both in 18 decimals/wei)
    function mntToUsd(uint256 mntAmount) external view returns (uint256) {
        require(_price > 0, "Invalid price");
        return (mntAmount * (10 ** DECIMALS)) / uint256(_price);
    }
    
    // Get MNT needed for USD cents (e.g., 1500 = $15.00)
    function getRequiredMnt(uint256 priceInUsdCents) external view returns (uint256) {
        uint256 usdWei = (priceInUsdCents * 1e18) / 100;
        return (usdWei * uint256(_price)) / (10 ** DECIMALS);
    }
}
