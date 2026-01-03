// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/LumaRootsUpgradeable.sol";
import "../src/MockPriceFeed.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployUpgradeable
 * @dev Deploy script for LumaRootsUpgradeable with UUPS proxy pattern
 * 
 * Usage:
 * 1. Set environment variables in .env:
 *    - PRIVATE_KEY: Deployer private key
 *    - MANTLE_SEPOLIA_RPC: https://rpc.sepolia.mantle.xyz
 * 
 * 2. Run deployment:
 *    forge script script/DeployUpgradeable.s.sol:DeployUpgradeable \
 *      --rpc-url $MANTLE_SEPOLIA_RPC \
 *      --broadcast \
 *      --verify \
 *      -vvvv
 */
contract DeployUpgradeable is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("===========================================");
        console.log("Deploying LumaRoots Upgradeable to Mantle Sepolia");
        console.log("===========================================");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy MockPriceFeed (for testnet only)
        console.log("Step 1: Deploying MockPriceFeed...");
        // Initial price: 1 EUR = 2 MNT (2.0 with 8 decimals = 200000000)
        MockPriceFeed priceFeed = new MockPriceFeed(2_00000000);
        console.log("MockPriceFeed deployed at:", address(priceFeed));
        console.log("Initial EUR/MNT price: 2.0 (1 EUR = 2 MNT)");
        console.log("");
        
        // 2. Deploy Implementation contract
        console.log("Step 2: Deploying LumaRootsUpgradeable implementation...");
        LumaRootsUpgradeable implementation = new LumaRootsUpgradeable();
        console.log("Implementation deployed at:", address(implementation));
        console.log("");
        
        // 3. Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            LumaRootsUpgradeable.initialize.selector,
            deployer // initialOwner
        );
        
        // 4. Deploy ERC1967 Proxy pointing to implementation
        console.log("Step 3: Deploying ERC1967 Proxy...");
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        console.log("Proxy deployed at:", address(proxy));
        console.log("");
        
        // 5. Verify deployment by calling proxy
        LumaRootsUpgradeable lumaRoots = LumaRootsUpgradeable(address(proxy));
        
        console.log("===========================================");
        console.log("Deployment Complete!");
        console.log("===========================================");
        console.log("");
        console.log("IMPORTANT - Save these addresses:");
        console.log("----------------------------------------");
        console.log("Proxy Address (use this!):", address(proxy));
        console.log("Implementation Address:", address(implementation));
        console.log("MockPriceFeed Address:", address(priceFeed));
        console.log("");
        console.log("Contract Info:");
        console.log("----------------------------------------");
        console.log("Name:", lumaRoots.name());
        console.log("Symbol:", lumaRoots.symbol());
        console.log("Owner:", lumaRoots.owner());
        console.log("Version:", lumaRoots.VERSION());
        console.log("Cooldown Time:", lumaRoots.cooldownTime(), "seconds");
        console.log("Min Purchase:", lumaRoots.minPurchaseAmount(), "wei");
        console.log("");
        console.log("For frontend, update contract.ts with:");
        console.log("  LUMAROOTS_ADDRESS:", address(proxy));
        console.log("  MOCK_PRICE_FEED_ADDRESS:", address(priceFeed));
        
        vm.stopBroadcast();
    }
}

/**
 * @title UpgradeContract
 * @dev Upgrade script for future versions
 * 
 * Usage:
 *    forge script script/DeployUpgradeable.s.sol:UpgradeContract \
 *      --rpc-url $MANTLE_SEPOLIA_RPC \
 *      --broadcast \
 *      -vvvv
 */
contract UpgradeContract is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS"); // Set this!
        
        console.log("===========================================");
        console.log("Upgrading LumaRoots Contract");
        console.log("===========================================");
        console.log("Proxy Address:", proxyAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy new implementation
        // Replace this with your new version contract
        LumaRootsUpgradeable newImplementation = new LumaRootsUpgradeable();
        console.log("New Implementation:", address(newImplementation));
        
        // Get proxy instance
        LumaRootsUpgradeable proxy = LumaRootsUpgradeable(proxyAddress);
        
        // Upgrade to new implementation
        proxy.upgradeToAndCall(address(newImplementation), "");
        
        console.log("===========================================");
        console.log("Upgrade Complete!");
        console.log("===========================================");
        console.log("New Version:", proxy.VERSION());
        
        vm.stopBroadcast();
    }
}
