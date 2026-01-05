// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/**
 * LumaRootsUpgradeable
 *
 * This is the main contract for the LumaRoots dApp. We built this to let
 * people grow a virtual forest while also donating to plant real trees
 * through Tree-Nation.
 *
 * How it works:
 * - New users get a free starter tree (claimed via gasless tx from Privy)
 * - Users water their forest daily to earn points
 * - Points can be spent to grow more virtual trees
 * - Users can also donate MNT to plant real trees and get an NFT certificate
 *
 * We use UUPS proxy so we can upgrade the contract later if needed (bug fixes,
 * new features, etc). The Pausable modifier lets us hit the brakes if something
 * goes wrong. ReentrancyGuard is there because we move funds around.
 *
 * Storage layout note: if you're upgrading, only append new state variables
 * at the bottom. Don't reorder or remove existing ones.
 *
 */
contract LumaRootsUpgradeable is 
    Initializable,
    ERC721URIStorageUpgradeable, 
    OwnableUpgradeable,
    PausableUpgradeable,
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
        uint256 amountPaid;      // Amount in MNT
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
    
    // Purchases (Real Trees)
    mapping(uint256 => Purchase) public purchases;
    mapping(address => uint256[]) public userPurchaseIds;
    uint256 private _purchaseIdCounter;
    
    // NFTs (Real Tree Certificates)
    uint256 private _tokenIdCounter;
    mapping(uint256 => uint256) public tokenIdToPurchaseId;  // Link NFT to purchase
    
    // Settings
    uint256 public minPurchaseAmount;

    // ============ NEW: Virtual Trees & Points System ============
    
    // Virtual trees (counter, not NFT)
    mapping(address => uint256) public virtualTreeCount;
    mapping(address => bool) public hasClaimedFreeTree;
    
    // Points system
    mapping(address => uint256) public userPoints;
    uint256 public pointsPerWater;           // Base points per water (default: 10)
    uint256 public streakBonusPoints;        // Bonus per streak day (default: 5)
    uint256 public maxStreakBonus;           // Max streak days for bonus (default: 7)
    uint256 public pointsPerVirtualTree;     // Cost to redeem virtual tree (default: 500)

    // Version tracking
    string public constant VERSION = "1.0.0";

    // ============ Events ============
    
    // Watering game events
    event PlantWatered(
        address indexed user, 
        uint256 newStreak, 
        uint256 totalWaterCount, 
        uint256 pointsEarned,
        uint256 totalPoints,
        uint256 timestamp
    );
    
    // Virtual tree events
    event FreeTreeClaimed(address indexed user, uint256 timestamp);
    event VirtualTreeRedeemed(address indexed user, uint256 pointsSpent, uint256 newTreeCount, uint256 timestamp);
    
    // Purchase events (Real Trees)
    event TreePurchased(
        uint256 indexed purchaseId,
        address indexed buyer,
        uint256 speciesId,
        uint256 projectId,
        uint256 amountPaid,
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
    event PointsSettingsUpdated(uint256 pointsPerWater, uint256 streakBonus, uint256 maxStreak, uint256 redeemCost);
    event ContractPaused(address indexed by, uint256 timestamp);
    event ContractUnpaused(address indexed by, uint256 timestamp);

    // ============ Constructor (disabled for upgradeable) ============
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    // Called once when we deploy the proxy. Sets up the NFT collection name,
    // owner address, and all the default game settings.
    function initialize(address initialOwner) public initializer {
        __ERC721_init("LumaRoots Tree Certificate", "LRTC");
        __ERC721URIStorage_init();
        __Ownable_init(initialOwner);
        __Pausable_init();

        _tokenIdCounter = 0;
        _purchaseIdCounter = 0;
        cooldownTime = 24 hours;
        minPurchaseAmount = 0.001 ether;
        
        // Default points economy - can be tweaked later via setPointsSettings()
        pointsPerWater = 10;
        streakBonusPoints = 5;
        maxStreakBonus = 7;
        pointsPerVirtualTree = 500;
    }

    // ============ UUPS Upgrade ============

    // Only the owner can swap out the implementation. This is the UUPS pattern.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Virtual Trees ============

    // New users call this to get their first tree. We sponsor the gas via Privy
    // so they don't need MNT to get started. One free tree per wallet.
    function claimFreeTree() external whenNotPaused {
        require(!hasClaimedFreeTree[msg.sender], "Already claimed free tree");
        
        hasClaimedFreeTree[msg.sender] = true;
        virtualTreeCount[msg.sender] = 1;
        
        emit FreeTreeClaimed(msg.sender, block.timestamp);
    }

    // Spend your hard-earned points to grow your forest! 500 points = 1 tree.
    function redeemPointsForTree(uint256 numberOfTrees) external whenNotPaused {
        require(numberOfTrees > 0, "Must redeem at least 1 tree");
        
        uint256 totalCost = pointsPerVirtualTree * numberOfTrees;
        require(userPoints[msg.sender] >= totalCost, "Not enough points");
        
        userPoints[msg.sender] -= totalCost;
        virtualTreeCount[msg.sender] += numberOfTrees;
        
        emit VirtualTreeRedeemed(msg.sender, totalCost, virtualTreeCount[msg.sender], block.timestamp);
    }

    // ============ Real Tree Purchases ============

    // This is where the magic happens - users donate MNT to plant a real tree.
    // The backend listens for TreePurchased events and handles the Tree-Nation API.
    // After confirmation, the backend calls mintCertificate() to give them the NFT.
    function purchaseTree(
        uint256 speciesId,
        uint256 projectId
    ) external payable nonReentrant whenNotPaused {
        require(msg.value >= minPurchaseAmount, "Below minimum purchase amount");
        require(speciesId > 0, "Invalid species ID");
        require(projectId > 0, "Invalid project ID");

        uint256 purchaseId = _purchaseIdCounter;
        _purchaseIdCounter += 1;

        purchases[purchaseId] = Purchase({
            buyer: msg.sender,
            speciesId: speciesId,
            projectId: projectId,
            amountPaid: msg.value,
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
            block.timestamp
        );
    }

    // Backend calls this after successfully planting the tree on Tree-Nation.
    // It mints the NFT certificate to the user's wallet.
    function mintCertificate(
        uint256 purchaseId,
        string memory tokenURI,
        string memory treeNationId
    ) external onlyOwner {
        Purchase storage purchase = purchases[purchaseId];

        require(purchase.buyer != address(0), "Purchase not found");
        require(purchase.processed, "Purchase not yet processed");
        require(!purchase.nftMinted, "NFT already minted");

        uint256 newTokenId = _tokenIdCounter;
        _tokenIdCounter += 1;
        
        _safeMint(purchase.buyer, newTokenId);
        _setTokenURI(newTokenId, tokenURI);
        
        tokenIdToPurchaseId[newTokenId] = purchaseId;
        purchase.nftMinted = true;

        emit CertificateMinted(newTokenId, purchase.buyer, purchaseId, treeNationId);
    }

    // Backend calls this when Tree-Nation API returns success. It's a simple
    // flag so we don't double-process purchases.
    function markPurchaseProcessed(uint256 purchaseId) external onlyOwner {
        Purchase storage purchase = purchases[purchaseId];
        require(purchase.buyer != address(0), "Purchase not found");
        require(!purchase.processed, "Already processed");
        
        purchase.processed = true;
    }

    // ============ Watering Game ============

    // The core daily engagement loop. Users water their forest once per day
    // and earn points. More trees = more points. Consecutive days = streak bonus.
    function waterPlant() external whenNotPaused {
        UserPlant storage plant = userPlants[msg.sender];
        
        require(
            block.timestamp > plant.lastWaterTime + cooldownTime,
            "Cooldown not finished"
        );

        uint256 totalTrees = getTotalTreeCount(msg.sender);
        require(totalTrees > 0, "No trees to water. Claim free tree first!");

        // Streak logic: reset if they missed more than 2x cooldown window
        if (plant.lastWaterTime == 0) {
            plant.waterStreak = 1;
        } else if (block.timestamp > plant.lastWaterTime + (cooldownTime * 2)) {
            plant.waterStreak = 1;
        } else {
            plant.waterStreak += 1;
        }

        plant.lastWaterTime = block.timestamp;
        plant.totalWaterCount += 1;
        
        // Points = (base × trees) + streak bonus
        uint256 basePoints = pointsPerWater * totalTrees;
        uint256 streakBonus = 0;
        
        if (plant.waterStreak > 1) {
            // Streak bonus: min(streak - 1, maxStreakBonus) × streakBonusPoints
            uint256 streakDays = plant.waterStreak - 1;
            if (streakDays > maxStreakBonus) {
                streakDays = maxStreakBonus;
            }
            streakBonus = streakDays * streakBonusPoints;
        }
        
        uint256 totalPointsEarned = basePoints + streakBonus;
        userPoints[msg.sender] += totalPointsEarned;
        
        emit PlantWatered(
            msg.sender, 
            plant.waterStreak, 
            plant.totalWaterCount, 
            totalPointsEarned,
            userPoints[msg.sender],
            block.timestamp
        );
    }

    // ============ Admin Functions ============

    // Emergency brake - stops all user actions if something goes wrong.
    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender, block.timestamp);
    }

    // All clear - resume normal operations.
    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender, block.timestamp);
    }

    // Tweak the watering cooldown (default 24h, but maybe we want faster for testing)
    function setCooldownTime(uint256 _seconds) external onlyOwner {
        require(_seconds > 0, "Must be > 0");
        uint256 old = cooldownTime;
        cooldownTime = _seconds;
        emit CooldownTimeUpdated(old, _seconds);
    }

    // Set minimum donation amount for real trees
    function setMinPurchaseAmount(uint256 _amount) external onlyOwner {
        uint256 old = minPurchaseAmount;
        minPurchaseAmount = _amount;
        emit MinPurchaseAmountUpdated(old, _amount);
    }

    // Tune the points economy if needed
    function setPointsSettings(
        uint256 _pointsPerWater,
        uint256 _streakBonusPoints,
        uint256 _maxStreakBonus,
        uint256 _pointsPerVirtualTree
    ) external onlyOwner {
        pointsPerWater = _pointsPerWater;
        streakBonusPoints = _streakBonusPoints;
        maxStreakBonus = _maxStreakBonus;
        pointsPerVirtualTree = _pointsPerVirtualTree;
        
        emit PointsSettingsUpdated(_pointsPerWater, _streakBonusPoints, _maxStreakBonus, _pointsPerVirtualTree);
    }

    // Gift points to users (for promos, contests, bug bounties, etc)
    function awardPoints(address user, uint256 amount) external onlyOwner {
        userPoints[user] += amount;
    }

    // Just in case funds get stuck somehow
    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    // ============ View Functions ============

    // Total trees a user has (virtual + real NFTs from donations)
    function getTotalTreeCount(address user) public view returns (uint256) {
        uint256 realTrees = userPurchaseIds[user].length;
        uint256 virtualTrees = virtualTreeCount[user];
        return realTrees + virtualTrees;
    }

    // Get everything about a user's forest in one call (saves RPC requests)
    function getUserForest(address user) external view returns (
        uint256 virtualTrees,
        uint256 realTrees,
        uint256 totalTrees,
        uint256 points,
        bool hasFreeTree
    ) {
        virtualTrees = virtualTreeCount[user];
        realTrees = userPurchaseIds[user].length;
        totalTrees = virtualTrees + realTrees;
        points = userPoints[user];
        hasFreeTree = hasClaimedFreeTree[user];
    }

    // Watering game stats for a user
    function getUserPlant(address user) external view returns (
        uint256 lastWaterTime,
        uint256 waterStreak,
        uint256 totalWaterCount
    ) {
        UserPlant storage plant = userPlants[user];
        return (plant.lastWaterTime, plant.waterStreak, plant.totalWaterCount);
    }

    // Check if user can water now (and how long until they can if not)
    function canWaterNow(address user) external view returns (bool canWater, uint256 timeRemaining) {
        UserPlant storage plant = userPlants[user];
        uint256 nextWaterTime = plant.lastWaterTime + cooldownTime;
        
        if (block.timestamp > nextWaterTime) {
            return (true, 0);
        } else {
            return (false, nextWaterTime - block.timestamp);
        }
    }

    // Preview how many points they'd get if they water now
    function calculateWaterPoints(address user) external view returns (
        uint256 basePoints,
        uint256 streakBonus,
        uint256 totalPoints
    ) {
        UserPlant storage plant = userPlants[user];
        uint256 totalTrees = getTotalTreeCount(user);
        
        if (totalTrees == 0) {
            return (0, 0, 0);
        }
        
        basePoints = pointsPerWater * totalTrees;
        
        // Calculate expected streak
        uint256 expectedStreak = plant.waterStreak;
        if (plant.lastWaterTime == 0) {
            expectedStreak = 1;
        } else if (block.timestamp > plant.lastWaterTime + (cooldownTime * 2)) {
            expectedStreak = 1;
        } else {
            expectedStreak += 1;
        }
        
        if (expectedStreak > 1) {
            uint256 streakDays = expectedStreak - 1;
            if (streakDays > maxStreakBonus) {
                streakDays = maxStreakBonus;
            }
            streakBonus = streakDays * streakBonusPoints;
        }
        
        totalPoints = basePoints + streakBonus;
    }

    // Purchases
    function getPurchase(uint256 purchaseId) external view returns (
        address buyer,
        uint256 speciesId,
        uint256 projectId,
        uint256 amountPaid,
        uint256 timestamp,
        bool processed,
        bool nftMinted
    ) {
        Purchase storage p = purchases[purchaseId];
        return (p.buyer, p.speciesId, p.projectId, p.amountPaid, p.timestamp, p.processed, p.nftMinted);
    }

    function getUserPurchases(address user) external view returns (uint256[] memory) {
        return userPurchaseIds[user];
    }

    function getUserPurchaseCount(address user) external view returns (uint256) {
        return userPurchaseIds[user].length;
    }

    // Points system settings
    function getPointsSettings() external view returns (
        uint256 _pointsPerWater,
        uint256 _streakBonusPoints,
        uint256 _maxStreakBonus,
        uint256 _pointsPerVirtualTree
    ) {
        return (pointsPerWater, streakBonusPoints, maxStreakBonus, pointsPerVirtualTree);
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
