// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockPriceFeed
 * @dev Mock oracle for EUR/MNT price conversion
 * @notice For hackathon/testing purposes only
 * 
 * Production should use Chainlink Price Feed or similar oracle
 * Chainlink on Mantle: https://docs.chain.link/data-feeds/price-feeds/addresses
 */
contract MockPriceFeed is Ownable {
    // Price with 8 decimals (Chainlink standard)
    // Example: 2_00000000 = 1 EUR = 2 MNT
    int256 private _price;
    uint8 private constant _decimals = 8;
    
    // Timestamp of last update
    uint256 private _updatedAt;
    
    // Description
    string public description = "EUR / MNT (Mock)";
    
    event PriceUpdated(int256 oldPrice, int256 newPrice, uint256 timestamp);
    
    /**
     * @param initialPrice Initial EUR/MNT price with 8 decimals
     *        Example: 2_00000000 means 1 EUR = 2 MNT
     */
    constructor(int256 initialPrice) Ownable(msg.sender) {
        require(initialPrice > 0, "Price must be positive");
        _price = initialPrice;
        _updatedAt = block.timestamp;
    }
    
    // ============ Chainlink-compatible Interface ============
    
    /**
     * @dev Returns the latest price data (Chainlink AggregatorV3Interface compatible)
     * @return roundId The round ID (mock: always 1)
     * @return answer The price with decimals
     * @return startedAt The timestamp when round started (mock: same as updatedAt)
     * @return updatedAt The timestamp of last update
     * @return answeredInRound The round ID when answer was computed (mock: always 1)
     */
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (1, _price, _updatedAt, _updatedAt, 1);
    }
    
    /**
     * @dev Returns the number of decimals
     */
    function decimals() external pure returns (uint8) {
        return _decimals;
    }
    
    /**
     * @dev Returns the latest price answer directly
     */
    function latestAnswer() external view returns (int256) {
        return _price;
    }
    
    // ============ Admin Functions ============
    
    /**
     * @dev Update the mock price (owner only)
     * @param newPrice New EUR/MNT price with 8 decimals
     */
    function updatePrice(int256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be positive");
        int256 oldPrice = _price;
        _price = newPrice;
        _updatedAt = block.timestamp;
        emit PriceUpdated(oldPrice, newPrice, block.timestamp);
    }
    
    // ============ Helper Functions ============
    
    /**
     * @dev Convert EUR amount to MNT
     * @param eurAmount Amount in EUR (with 18 decimals, wei-style)
     * @return mntAmount Amount in MNT (with 18 decimals)
     * 
     * Example: 
     *   eurAmount = 1 EUR = 1e18
     *   price = 2e8 (1 EUR = 2 MNT)
     *   mntAmount = (1e18 * 2e8) / 1e8 = 2e18 = 2 MNT
     */
    function eurToMnt(uint256 eurAmount) external view returns (uint256 mntAmount) {
        require(_price > 0, "Invalid price");
        return (eurAmount * uint256(_price)) / (10 ** _decimals);
    }
    
    /**
     * @dev Convert MNT amount to EUR
     * @param mntAmount Amount in MNT (with 18 decimals)
     * @return eurAmount Amount in EUR (with 18 decimals)
     */
    function mntToEur(uint256 mntAmount) external view returns (uint256 eurAmount) {
        require(_price > 0, "Invalid price");
        return (mntAmount * (10 ** _decimals)) / uint256(_price);
    }
    
    /**
     * @dev Get required MNT for a EUR price (view helper)
     * @param priceInEurCents Price in EUR cents (e.g., 1500 = 15.00 EUR)
     * @return requiredMnt Amount of MNT needed (in wei)
     */
    function getRequiredMnt(uint256 priceInEurCents) external view returns (uint256 requiredMnt) {
        // Convert cents to wei (18 decimals)
        uint256 eurWei = (priceInEurCents * 1e18) / 100;
        // Convert to MNT
        return (eurWei * uint256(_price)) / (10 ** _decimals);
    }
}
