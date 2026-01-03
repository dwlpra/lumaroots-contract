// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/**
 * @title LumaRootsUpgradeable
 * @dev A Web3 platform for purchasing real trees through Tree-Nation
 *      Upgradeable via UUPS proxy pattern for future feature development
 * 
 * Flow:
 * 1. User browses projects and species on frontend
 * 2. User purchases tree by sending native token (converted from EUR price)
 * 3. Contract records purchase and transfers funds to owner
 * 4. Backend listens to TreePurchased event
 * 5. Backend calls Tree Nation API to plant real tree
 * 6. Backend calls mintCertificate() to mint NFT to user
 * 7. User receives NFT Certificate of real tree planted!
 * 
 * Separate Feature: Watering Game (for engagement, not blocking purchases)
 * 
 * Version: 1.0.0
 */
contract LumaRootsUpgradeable is 
    Initializable,
    ERC721URIStorageUpgradeable, 
    OwnableUpgradeable, 
    ReentrancyGuard,
    UUPSUpgradeable 
{
    
    // ============ Structs ============
    struct UserPlant {
        uint256 lastWaterTime;
        uint256 waterStreak;
        uint256 totalWaterCount;
    }

    struct Purchase {
        address buyer;
        uint256 speciesId;
        uint256 projectId;
        uint256 amountPaid;      // Amount in native token (MNT, ETH, etc)
        uint256 priceEUR;        // Original price in EUR (6 decimals)
        uint256 timestamp;
        bool processed;          // Backend has processed this purchase
        bool nftMinted;          // NFT certificate has been minted
    }

    // ============ State Variables ============
    // IMPORTANT: Never change the order of these variables in upgrades!
    // Only append new variables at the end.
    
    // Watering game
    mapping(address => UserPlant) public userPlants;
    uint256 public cooldownTime;
    
    // Purchases
    mapping(uint256 => Purchase) public purchases;
    mapping(address => uint256[]) public userPurchaseIds;
    uint256 private _purchaseIdCounter;
    
    // NFTs
    uint256 private _tokenIdCounter;
    mapping(uint256 => uint256) public tokenIdToPurchaseId;  // Link NFT to purchase
    
    // Settings
    uint256 public minPurchaseAmount;

    // Version tracking for upgrades
    string public constant VERSION = "1.0.0";

    // ============ Events ============
    
    // Watering game events
    event PlantWatered(address indexed user, uint256 newStreak, uint256 totalWaterCount, uint256 timestamp);
    
    // Purchase events
    event TreePurchased(
        uint256 indexed purchaseId,
        address indexed buyer,
        uint256 speciesId,
        uint256 projectId,
        uint256 amountPaid,
        uint256 priceEUR,
        uint256 timestamp
    );
    
    // NFT events
    event CertificateMinted(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 indexed purchaseId,
        string treeNationId
    );
    
    // Admin events
    event CooldownTimeUpdated(uint256 oldCooldown, uint256 newCooldown);
    event MinPurchaseAmountUpdated(uint256 oldMin, uint256 newMin);

    // ============ Constructor (disabled for upgradeable) ============
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer (replaces constructor) ============

    /**
     * @dev Initialize the contract (called once during proxy deployment)
     * @param initialOwner The address that will own the contract
     */
    function initialize(address initialOwner) public initializer {
        __ERC721_init("LumaRoots Tree Certificate", "LRTC");
        __ERC721URIStorage_init();
        __Ownable_init(initialOwner);

        _tokenIdCounter = 0;
        _purchaseIdCounter = 0;
        cooldownTime = 24 hours;
        minPurchaseAmount = 0.001 ether;
    }

    // ============ UUPS Upgrade Authorization ============

    /**
     * @dev Required by UUPS pattern - only owner can upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Purchase Functions ============

    /**
     * @dev Purchase a real tree
     * @param speciesId The Tree-Nation species ID
     * @param projectId The Tree-Nation project ID
     * @param priceEUR The price in EUR (6 decimals, e.g., 1000000 = €1.00)
     */
    function purchaseTree(
        uint256 speciesId,
        uint256 projectId,
        uint256 priceEUR
    ) external payable nonReentrant {
        require(msg.value >= minPurchaseAmount, "Below minimum purchase amount");
        require(speciesId > 0, "Invalid species ID");
        require(projectId > 0, "Invalid project ID");

        // Create purchase record
        uint256 purchaseId = _purchaseIdCounter;
        _purchaseIdCounter += 1;

        purchases[purchaseId] = Purchase({
            buyer: msg.sender,
            speciesId: speciesId,
            projectId: projectId,
            amountPaid: msg.value,
            priceEUR: priceEUR,
            timestamp: block.timestamp,
            processed: false,
            nftMinted: false
        });

        userPurchaseIds[msg.sender].push(purchaseId);

        // Transfer funds to owner (for Tree Nation credit purchase)
        (bool success, ) = payable(owner()).call{value: msg.value}("");
        require(success, "Transfer to owner failed");

        emit TreePurchased(
            purchaseId,
            msg.sender,
            speciesId,
            projectId,
            msg.value,
            priceEUR,
            block.timestamp
        );
    }

    /**
     * @dev Mint certificate NFT to user (called by backend after Tree Nation confirmation)
     * @param purchaseId The purchase ID
     * @param tokenURI The IPFS metadata URI with tree info
     * @param treeNationId The Tree Nation tree/certificate ID
     */
    function mintCertificate(
        uint256 purchaseId,
        string memory tokenURI,
        string memory treeNationId
    ) external onlyOwner {
        Purchase storage purchase = purchases[purchaseId];

        require(purchase.buyer != address(0), "Purchase not found");
        require(purchase.processed, "Purchase not yet processed");
        require(!purchase.nftMinted, "NFT already minted");

        // Mint NFT to buyer
        uint256 newTokenId = _tokenIdCounter;
        _tokenIdCounter += 1;
        
        _safeMint(purchase.buyer, newTokenId);
        _setTokenURI(newTokenId, tokenURI);
        
        // Link NFT to purchase
        tokenIdToPurchaseId[newTokenId] = purchaseId;
        purchase.nftMinted = true;

        emit CertificateMinted(newTokenId, purchase.buyer, purchaseId, treeNationId);
    }

    /**
     * @dev Mark purchase as processed (called by backend after Tree Nation API success)
     * @param purchaseId The purchase ID
     */
    function markPurchaseProcessed(uint256 purchaseId) external onlyOwner {
        Purchase storage purchase = purchases[purchaseId];
        require(purchase.buyer != address(0), "Purchase not found");
        require(!purchase.processed, "Already processed");
        
        purchase.processed = true;
    }

    // ============ Watering Game Functions ============

    /**
     * @dev Water the user's virtual plant. Can only be called once per cooldown period.
     * This is a separate gamification feature, not related to tree purchases.
     */
    function waterPlant() external {
        UserPlant storage plant = userPlants[msg.sender];
        
        require(
            block.timestamp > plant.lastWaterTime + cooldownTime,
            "Cooldown not finished"
        );

        // Reset streak if missed watering window (2x cooldown)
        if (plant.lastWaterTime == 0) {
            plant.waterStreak = 1;
        } else if (block.timestamp > plant.lastWaterTime + (cooldownTime * 2)) {
            plant.waterStreak = 1;  // Reset streak
        } else {
            plant.waterStreak += 1;
        }

        plant.lastWaterTime = block.timestamp;
        plant.totalWaterCount += 1;
        
        emit PlantWatered(msg.sender, plant.waterStreak, plant.totalWaterCount, block.timestamp);
    }

    // ============ Admin Functions ============

    function setCooldownTime(uint256 _seconds) external onlyOwner {
        require(_seconds > 0, "Must be > 0");
        uint256 old = cooldownTime;
        cooldownTime = _seconds;
        emit CooldownTimeUpdated(old, _seconds);
    }

    function setMinPurchaseAmount(uint256 _amount) external onlyOwner {
        uint256 old = minPurchaseAmount;
        minPurchaseAmount = _amount;
        emit MinPurchaseAmountUpdated(old, _amount);
    }

    // Emergency withdraw (in case of stuck funds)
    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    // ============ View Functions ============

    // User plant (watering game)
    function getUserPlant(address user) external view returns (
        uint256 lastWaterTime,
        uint256 waterStreak,
        uint256 totalWaterCount
    ) {
        UserPlant storage plant = userPlants[user];
        return (plant.lastWaterTime, plant.waterStreak, plant.totalWaterCount);
    }

    function canWaterNow(address user) external view returns (bool canWater, uint256 timeRemaining) {
        UserPlant storage plant = userPlants[user];
        uint256 nextWaterTime = plant.lastWaterTime + cooldownTime;
        
        if (block.timestamp > nextWaterTime) {
            return (true, 0);
        } else {
            return (false, nextWaterTime - block.timestamp);
        }
    }

    // Purchases
    function getPurchase(uint256 purchaseId) external view returns (
        address buyer,
        uint256 speciesId,
        uint256 projectId,
        uint256 amountPaid,
        uint256 priceEUR,
        uint256 timestamp,
        bool processed,
        bool nftMinted
    ) {
        Purchase storage p = purchases[purchaseId];
        return (p.buyer, p.speciesId, p.projectId, p.amountPaid, p.priceEUR, p.timestamp, p.processed, p.nftMinted);
    }

    function getUserPurchases(address user) external view returns (uint256[] memory) {
        return userPurchaseIds[user];
    }

    function getUserPurchaseCount(address user) external view returns (uint256) {
        return userPurchaseIds[user].length;
    }

    // Stats
    function totalSupply() external view returns (uint256) {
        return _tokenIdCounter;
    }

    function totalPurchases() external view returns (uint256) {
        return _purchaseIdCounter;
    }

    // Get implementation address (for verification)
    function getImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }
}
