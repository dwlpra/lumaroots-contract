// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/LumaRoots.sol";
import "../src/MockPriceFeed.sol";

/**
 * @title DeployLumaRoots
 * @dev Deploy script for LumaRoots and MockPriceFeed to Mantle Sepolia
 * 
 * Usage:
 *   # Load environment variables
 *   source .env
 *   
 *   # Deploy to Mantle Sepolia
 *   forge script script/Deploy.s.sol:DeployLumaRoots --rpc-url $MANTLE_SEPOLIA_RPC --broadcast --verify -vvvv
 *   
 *   # Deploy locally (anvil)
 *   forge script script/Deploy.s.sol:DeployLumaRoots --fork-url http://localhost:8545 --broadcast
 */
contract DeployLumaRoots is Script {
    // Default EUR/MNT price: 1 EUR = 2 MNT (with 8 decimals)
    int256 constant DEFAULT_EUR_MNT_PRICE = 2_00000000;
    
    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== LumaRoots Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy MockPriceFeed
        console.log("Deploying MockPriceFeed...");
        MockPriceFeed priceFeed = new MockPriceFeed(DEFAULT_EUR_MNT_PRICE);
        console.log("MockPriceFeed deployed at:", address(priceFeed));
        
        // 2. Deploy LumaRoots
        console.log("Deploying LumaRoots...");
        LumaRoots lumaRoots = new LumaRoots();
        console.log("LumaRoots deployed at:", address(lumaRoots));
        
        vm.stopBroadcast();
        
        // Log deployment summary
        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("");
        console.log("MockPriceFeed:", address(priceFeed));
        console.log("LumaRoots:", address(lumaRoots));
        console.log("");
        console.log("Next steps:");
        console.log("1. Update frontend config with contract addresses");
        console.log("2. Update backend config with contract addresses");
        console.log("3. Verify contracts on explorer (if --verify flag used)");
        
        // Verify initial state
        console.log("");
        console.log("=== Contract State ===");
        console.log("LumaRoots Owner:", lumaRoots.owner());
        console.log("LumaRoots Name:", lumaRoots.name());
        console.log("LumaRoots Symbol:", lumaRoots.symbol());
        console.log("MockPriceFeed Price (8 decimals):", uint256(priceFeed.latestAnswer()));
    }
}

/**
 * @title DeployLumaRootsLocal
 * @dev Deploy script for local testing with Anvil
 */
contract DeployLumaRootsLocal is Script {
    int256 constant DEFAULT_EUR_MNT_PRICE = 2_00000000;
    
    function run() external {
        // Use default anvil private key
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        
        vm.startBroadcast(deployerPrivateKey);
        
        MockPriceFeed priceFeed = new MockPriceFeed(DEFAULT_EUR_MNT_PRICE);
        LumaRoots lumaRoots = new LumaRoots();
        
        vm.stopBroadcast();
        
        console.log("MockPriceFeed:", address(priceFeed));
        console.log("LumaRoots:", address(lumaRoots));
    }
}
