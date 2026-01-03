// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ROOTS Token
 * @dev GameFi utility token for LumaRoots ecosystem
 * 
 * Token Economics:
 * - Users earn ROOTS for daily watering (10 ROOTS/water)
 * - Bonus multipliers for streaks (1.5x at 7 days, 2x at 30 days)
 * - Weather bonuses (rainy = 1.5x, storm = 2x)
 * - Spend ROOTS for rare plants, boosts, cosmetics
 * - Staking for multiplied tree donation impact
 */
contract RootsToken is ERC20, Ownable, ReentrancyGuard {
    
    // ============ Constants ============
    uint256 public constant BASE_WATER_REWARD = 10 * 10**18; // 10 ROOTS per water
    uint256 public constant MAX_DAILY_REWARDS = 1000 * 10**18; // 1000 ROOTS max per day
    uint256 public constant TOTAL_SUPPLY = 1000000000 * 10**18; // 1B ROOTS total
    
    // ============ Structs ============
    struct UserRewards {
        uint256 dailyEarned;
        uint256 lastClaimDay;
        uint256 totalEarned;
        uint256 stakedAmount;
        uint256 stakeStartTime;
    }
    
    struct StreakMultiplier {
        uint256 minStreak;
        uint256 multiplierBPS; // Basis points (10000 = 100%)
    }
    
    // ============ State Variables ============
    mapping(address => UserRewards) public userRewards;
    mapping(address => bool) public gameContracts; // Authorized contracts that can mint rewards
    
    StreakMultiplier[] public streakMultipliers;
    
    uint256 public totalStaked;
    uint256 public stakingRewardRate = 500; // 5% APY in basis points
    
    // ============ Events ============
    event RewardsClaimed(address indexed user, uint256 amount, string action);
    event TokensStaked(address indexed user, uint256 amount);
    event TokensUnstaked(address indexed user, uint256 amount);
    event StreakBonus(address indexed user, uint256 streak, uint256 bonus);
    
    // ============ Constructor ============
    constructor() ERC20("LumaRoots Token", "ROOTS") Ownable(msg.sender) {
        // Initialize streak multipliers
        streakMultipliers.push(StreakMultiplier(7, 15000));   // 7 days = 1.5x
        streakMultipliers.push(StreakMultiplier(14, 17500));  // 14 days = 1.75x  
        streakMultipliers.push(StreakMultiplier(30, 20000));  // 30 days = 2x
        
        // Mint initial supply for liquidity and rewards
        _mint(address(this), TOTAL_SUPPLY);
        
        // Transfer portion to owner for distribution
        _transfer(address(this), owner(), TOTAL_SUPPLY / 10); // 10% to owner
    }
    
    // ============ Game Integration ============
    
    /**
     * @dev Reward user for watering plant with streak and weather bonuses
     */
    function rewardWaterAction(
        address user, 
        uint256 waterStreak, 
        uint256 weatherMultiplierBPS
    ) external onlyGameContract nonReentrant {
        require(user != address(0), "Invalid user address");
        
        UserRewards storage rewards = userRewards[user];
        uint256 currentDay = block.timestamp / 86400;
        
        // Reset daily counter if new day
        if (rewards.lastClaimDay != currentDay) {
            rewards.dailyEarned = 0;
            rewards.lastClaimDay = currentDay;
        }
        
        // Calculate base reward
        uint256 baseReward = BASE_WATER_REWARD;
        
        // Apply streak multiplier
        uint256 streakMultiplier = getStreakMultiplier(waterStreak);
        uint256 rewardAfterStreak = (baseReward * streakMultiplier) / 10000;
        
        // Apply weather multiplier
        uint256 finalReward = (rewardAfterStreak * weatherMultiplierBPS) / 10000;
        
        // Check daily limit
        if (rewards.dailyEarned + finalReward > MAX_DAILY_REWARDS) {
            finalReward = MAX_DAILY_REWARDS - rewards.dailyEarned;
        }
        
        if (finalReward > 0) {
            rewards.dailyEarned += finalReward;
            rewards.totalEarned += finalReward;
            
            // Transfer tokens from contract to user
            _transfer(address(this), user, finalReward);
            
            emit RewardsClaimed(user, finalReward, "water_plant");
            
            // Emit streak bonus event if applicable
            if (streakMultiplier > 10000) {
                emit StreakBonus(user, waterStreak, streakMultiplier);
            }
        }
    }
    
    /**
     * @dev Reward user for planting real tree
     */
    function rewardTreePlanting(address user, uint256 donationAmountUSD) external onlyGameContract nonReentrant {
        require(user != address(0), "Invalid user address");
        
        // 1 ROOTS per $0.01 donated (scaled reward)
        uint256 treeReward = donationAmountUSD * 100 * 10**18;
        
        UserRewards storage rewards = userRewards[user];
        rewards.totalEarned += treeReward;
        
        _transfer(address(this), user, treeReward);
        
        emit RewardsClaimed(user, treeReward, "plant_tree");
    }
    
    // ============ Staking System ============
    
    /**
     * @dev Stake ROOTS tokens for additional benefits
     */
    function stakeTokens(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0 tokens");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        UserRewards storage rewards = userRewards[msg.sender];
        
        // Claim any pending staking rewards first
        if (rewards.stakedAmount > 0) {
            claimStakingRewards();
        }
        
        // Transfer tokens to contract
        _transfer(msg.sender, address(this), amount);
        
        rewards.stakedAmount += amount;
        rewards.stakeStartTime = block.timestamp;
        totalStaked += amount;
        
        emit TokensStaked(msg.sender, amount);
    }
    
    /**
     * @dev Unstake ROOTS tokens and claim rewards
     */
    function unstakeTokens(uint256 amount) external nonReentrant {
        UserRewards storage rewards = userRewards[msg.sender];
        require(rewards.stakedAmount >= amount, "Insufficient staked amount");
        
        // Claim staking rewards first
        claimStakingRewards();
        
        rewards.stakedAmount -= amount;
        totalStaked -= amount;
        
        // Transfer tokens back to user
        _transfer(address(this), msg.sender, amount);
        
        emit TokensUnstaked(msg.sender, amount);
    }
    
    /**
     * @dev Claim staking rewards
     */
    function claimStakingRewards() public nonReentrant {
        UserRewards storage rewards = userRewards[msg.sender];
        
        if (rewards.stakedAmount == 0) return;
        
        uint256 timeStaked = block.timestamp - rewards.stakeStartTime;
        uint256 stakingReward = (rewards.stakedAmount * stakingRewardRate * timeStaked) / (10000 * 365 days);
        
        if (stakingReward > 0) {
            rewards.stakeStartTime = block.timestamp;
            _transfer(address(this), msg.sender, stakingReward);
            
            emit RewardsClaimed(msg.sender, stakingReward, "staking_reward");
        }
    }
    
    // ============ Utility Functions ============
    
    /**
     * @dev Get streak multiplier based on current streak
     */
    function getStreakMultiplier(uint256 streak) public view returns (uint256) {
        uint256 multiplier = 10000; // 100% base
        
        for (uint256 i = streakMultipliers.length; i > 0; i--) {
            if (streak >= streakMultipliers[i-1].minStreak) {
                multiplier = streakMultipliers[i-1].multiplierBPS;
                break;
            }
        }
        
        return multiplier;
    }
    
    /**
     * @dev Get user staking info
     */
    function getUserStakingInfo(address user) external view returns (
        uint256 stakedAmount,
        uint256 pendingRewards,
        uint256 totalEarned
    ) {
        UserRewards memory rewards = userRewards[user];
        stakedAmount = rewards.stakedAmount;
        totalEarned = rewards.totalEarned;
        
        if (rewards.stakedAmount > 0) {
            uint256 timeStaked = block.timestamp - rewards.stakeStartTime;
            pendingRewards = (rewards.stakedAmount * stakingRewardRate * timeStaked) / (10000 * 365 days);
        }
    }
    
    // ============ Admin Functions ============
    
    /**
     * @dev Add authorized game contract
     */
    function addGameContract(address gameContract) external onlyOwner {
        gameContracts[gameContract] = true;
    }
    
    /**
     * @dev Remove authorized game contract
     */
    function removeGameContract(address gameContract) external onlyOwner {
        gameContracts[gameContract] = false;
    }
    
    /**
     * @dev Update staking reward rate (only owner)
     */
    function updateStakingRate(uint256 newRate) external onlyOwner {
        require(newRate <= 2000, "Rate too high"); // Max 20% APY
        stakingRewardRate = newRate;
    }
    
    /**
     * @dev Emergency withdraw (only owner)
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        require(amount <= balanceOf(address(this)) - totalStaked, "Cannot withdraw staked tokens");
        _transfer(address(this), owner(), amount);
    }
    
    // ============ Modifiers ============
    
    modifier onlyGameContract() {
        require(gameContracts[msg.sender], "Not authorized game contract");
        _;
    }
}