

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


/// @author Deepak Pal: https://github.com/deepakpalrocks

contract CustomStreamRewarder is Ownable{
    using SafeERC20 for IERC20;

    struct Reward {
        uint256 periodFinish;
        uint256 constantOfRewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        uint256 queuedRewards; 
    }

    struct UserReward {
        uint256 userRewardPerTokenPaid;
        uint256 rewards;
    }

    address public receiptToken;
    address[] public rewardTokens;

    uint256 public duration; // duration over which harvested rewards are distributed every time
    // Current reward rate = a_RewardRate * time + b_RewardRate
    uint256 public slopeOfRewardRate;
    uint256 public constantOfRewardRate;
    uint256 public constant DENOMINATOR = 10 ** 12;
    uint256 public receiptTokenDecimal;

    mapping(address => Reward) public rewards;
    mapping(address => bool) public isRewardToken;

    // userRewards[rewardToken][account]
    mapping(address => mapping(address => UserReward)) public userRewards;
    mapping(address => uint256) public userLastTime;
    mapping(address => uint256) public userAmountTime;
    mapping(address => bool) public isRewardQueuer;

    event RewardTokenAdded(address indexed _rewardToken);
    event RewardPaid(address indexed _user, address indexed _receiver, uint256 _reward, address indexed _rewardToken);
    event RewardQueued(address rewardToken, uint256 rewardAmount);
    event QueuerStatusUpdated(address rewardQueuer, bool status);
    event MasterCampieUpdated(address oldMasterCampie, address newMasterCampie);

    /* ================================= Errors ===========================*/

    error OnlyRewardQueuer();
    error OnlyMasterCampie();
    error InvalidToken();
    error ZeroAddress();

    /* ================================= Constructor ===========================*/

    constructor(address _receiptToken, address _rewardQueuer, uint256 _duration, uint256 _slope) {

        slopeOfRewardRate = _slope;
        receiptToken = _receiptToken;
        isRewardQueuer[_rewardQueuer] = true;
        duration = _duration;
    }

    /* ================= Modifiers ===============================*/

    modifier onlyRewardQueuer() {
        if (!isRewardQueuer[msg.sender]) {
            revert OnlyRewardQueuer();
        }
        _;
    }

    /* ============================= External Getters ======================*/

    function totalStaked() public view returns (uint256) {
        return IERC20(receiptToken).totalSupply();
    }

    function balanceOf(address _account) public view virtual returns (uint256) {
        return IERC20(receiptToken).balanceOf(_account);
    }

    function lastTimeRewardApplicable(address _rewardToken) public view returns (uint256) {
        return Math.min(block.timestamp, rewards[_rewardToken].periodFinish);
    }

    function getRewardRateAtTime(address _rewardToken, uint256 _timeStamp) public view returns (uint256) {
        Reward memory reward = rewards[_rewardToken];
        return slopeOfRewardRate * _timeStamp / DENOMINATOR + reward.constantOfRewardRate;
    }

    // returns in decimal of reward token decimal + DENOMINATOR to work for small decimal reward tokens
    function rewardPerToken(address _rewardToken) public view returns (uint256) {
        Reward memory reward = rewards[_rewardToken];

        if (totalStaked() == 0) {
            return reward.rewardPerTokenStored;
        }
        // Area under the linear graph with non-zero constant term will give the Rewards accumullated, 
        // which will be area of triangle + area of rectangle for reward rate vz time graph
        // area = delTime * old Reward rate + 1/2* delTime * (new reward Rate - old reward rate) = delTime/2(new reward rate + old reward rate)
        uint256 lastUpdateTimeStamp = reward.lastUpdateTime;
        uint256 latestApplicableTimeStamp = lastTimeRewardApplicable(_rewardToken);
        uint256 timeDiff = latestApplicableTimeStamp -  lastUpdateTimeStamp;
        uint256 totalRewardTokensAccumuated = timeDiff * (
            getRewardRateAtTime(_rewardToken, latestApplicableTimeStamp) + getRewardRateAtTime(_rewardToken, lastUpdateTimeStamp)
        ); 

        return reward.rewardPerTokenStored + (totalRewardTokensAccumuated * (10 ** receiptTokenDecimal) / (totalStaked()));
    }

    function getRewardLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    function earned(address _account, address _rewardToken) public view returns (uint256) {
        UserReward memory userReward = userRewards[_rewardToken][_account];
        return (
            (balanceOf(_account) * (rewardPerToken(_rewardToken) - userReward.userRewardPerTokenPaid))
                / (DENOMINATOR * (10 ** receiptTokenDecimal))
        ) + userReward.rewards;
    }

    function getUserAmountTime(address _account) public view returns (uint256) {
        uint256 lastTime = userLastTime[_account];
        if (lastTime == 0) {
            return 0;
        }
        uint256 userBalance = balanceOf(_account);
        if (userBalance == 0) {
            return userAmountTime[_account];
        }

        return userAmountTime[_account] + ((block.timestamp - lastTime) * userBalance);
    }

    function allEarned(address _account) external view returns (uint256[] memory pendingBonusRewards) {
        uint256 length = rewardTokens.length;
        pendingBonusRewards = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            pendingBonusRewards[i] = earned(_account, rewardTokens[i]);
        }

        return pendingBonusRewards;
    }

    function rewardTokenInfos()
        external
        view
        returns (address[] memory bonusTokenAddresses, string[] memory bonusTokenSymbols)
    {
        uint256 rewardTokensLength = rewardTokens.length;
        bonusTokenAddresses = new address[](rewardTokensLength);
        bonusTokenSymbols = new string[](rewardTokensLength);
        for (uint256 i; i < rewardTokensLength; i++) {
            bonusTokenAddresses[i] = rewardTokens[i];
            bonusTokenSymbols[i] = IERC20Metadata(address(bonusTokenAddresses[i])).symbol();
        }
    }

    /* ================ External Functions =================== */

    function updateFor(address _account) public {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            Reward storage reward = rewards[rewardToken];
            reward.rewardPerTokenStored = rewardPerToken(rewardToken);
            reward.lastUpdateTime = lastTimeRewardApplicable(rewardToken);

            UserReward storage userReward = userRewards[rewardToken][_account];
            userReward.rewards = earned(_account, rewardToken);
            userReward.userRewardPerTokenPaid = rewards[rewardToken].rewardPerTokenStored;
        }

        userAmountTime[_account] = getUserAmountTime(_account);
        userLastTime[_account] = block.timestamp;
    }

    function getRewards(address _account, address[] memory _rewardTokens) public 
    // onlyMasterChef
    {
        updateFor(_account);

        for (uint256 index = 0; index < _rewardTokens.length; ++index) {
            address rewardToken = _rewardTokens[index];
            _sendReward(_account, _account, rewardToken);
        }
    }

    function getReward(address _account) external 
    // onlyMasterCampie
     returns (bool) {
        updateFor(_account);

        for (uint256 index = 0; index < rewardTokens.length; ++index) {
            address rewardToken = rewardTokens[index];
            _sendReward(_account, _account, rewardToken);
        }
        return true;
    }

    function donateRewards(address _rewardToken, uint256 _rewards) external {
        if (!isRewardToken[_rewardToken]) {
            revert InvalidToken();
        }

        IERC20(_rewardToken).safeTransferFrom(msg.sender, address(this), _rewards);
        _provisionReward(_rewards, _rewardToken);
        emit RewardQueued(_rewardToken, _rewards);
    }

    function queueNewRewards(uint256 _rewards, address _rewardToken) external onlyRewardQueuer returns (bool) {
        _addRewardToken(_rewardToken);

        IERC20(_rewardToken).safeTransferFrom(msg.sender, address(this), _rewards);
        _provisionReward(_rewards, _rewardToken);
        emit RewardQueued(_rewardToken, _rewards);

        return true;
    }

    /* ===================================== Internal Functions ======================================== */

    function _provisionReward(uint256 _rewards, address _rewardToken) internal {
        _rewards = _rewards * DENOMINATOR; // to support small deciaml rewards

        Reward storage rewardInfo = rewards[_rewardToken];

        if (totalStaked() == 0) {
            rewardInfo.queuedRewards = rewardInfo.queuedRewards + _rewards;
            return;
        }

        rewardInfo.rewardPerTokenStored = rewardPerToken(_rewardToken);
        _rewards = _rewards + rewardInfo.queuedRewards;
        rewardInfo.queuedRewards = 0;

        // Update the constant of the equation-
        // using rewardstoQueue = delTime/2 *(rate at finish time of DURATION + rate at start time of DURATION)
        // c = _rewards / DURATION - (slope*(finishTime + startTime)/2);

        if (block.timestamp >= rewardInfo.periodFinish) {
            rewardInfo.constantOfRewardRate = _rewards / duration - slopeOfRewardRate * (block.timestamp * 2 + duration)/ DENOMINATOR;
        } else {
            uint256 currentTime = block.timestamp;
            uint256 finishTime = rewardInfo.periodFinish;
            uint256 remainingTime = finishTime - currentTime;
            uint256 leftover = remainingTime * (
                getRewardRateAtTime(_rewardToken, finishTime) + getRewardRateAtTime(_rewardToken, currentTime)
            );
            
            _rewards = _rewards + leftover;
            rewardInfo.constantOfRewardRate = _rewards / duration - slopeOfRewardRate * (block.timestamp * 2 + duration) / DENOMINATOR;
        }
        rewardInfo.lastUpdateTime = block.timestamp;
        rewardInfo.periodFinish = block.timestamp + duration;
    }

    function _addRewardToken(address _rewardToken) internal {
        if (_rewardToken == address(0)) {
            revert ZeroAddress();
        }
        if (isRewardToken[_rewardToken]) {
            return;
        }
        rewardTokens.push(_rewardToken);
        isRewardToken[_rewardToken] = true;

        emit RewardTokenAdded(_rewardToken);
    }

    function _sendReward(address _account, address _receiver, address _rewardToken) internal virtual {
        uint256 reward = userRewards[_rewardToken][_account].rewards;
        if (reward > 0) {
            userRewards[_rewardToken][_account].rewards = 0;

            IERC20(_rewardToken).safeTransfer(_receiver, reward);
            emit RewardPaid(_account, _receiver, reward, _rewardToken);
        }
    }

    /* ======================== Admin Functions ===================================== */

    function setRewardQueuerStatus(address _rewardQueuer, bool status) external onlyOwner {
        isRewardQueuer[_rewardQueuer] = status;

        emit QueuerStatusUpdated(_rewardQueuer, status);
    }

}
