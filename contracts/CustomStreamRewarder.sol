

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";


/// @author Deepak Pal: https://github.com/deepakpalrocks

contract CustomStreamRewarder is Ownable{
    using SafeERC20 for IERC20;

    struct Reward {
        uint256 periodFinish;
        int256 coefficient_c;
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
    // Current reward rate = coefficient_a * timestamp ^2 + coefficient_b * timestamp + codefficient_c 
    uint256 public coefficient_a;
    uint256 public coefficient_b;
    // uint256 public constantOfRewardRate;
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

    constructor(address _receiptToken, address _rewardQueuer, uint256 _duration, uint256 _coefficient_a, uint256 _coefficient_b) {

        coefficient_a = _coefficient_a;
        coefficient_b = _coefficient_b;
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
        int256 rewardRate = int256(coefficient_a * _timeStamp * _timeStamp 
            +  coefficient_b * _timeStamp )
            + reward.coefficient_c;
        return uint256(rewardRate) / DENOMINATOR;
    }

    function returnTimeStamp() public view returns(uint256){
        return block.timestamp;
    }

    // returns in decimal of reward token decimal + DENOMINATOR to work for small decimal reward tokens
    function rewardPerToken(address _rewardToken) public view returns (uint256) {
        Reward memory reward = rewards[_rewardToken];

        if (totalStaked() == 0) {
            return reward.rewardPerTokenStored;
        }
        
        uint256 lastUpdateTimeStamp = reward.lastUpdateTime;
        uint256 latestApplicableTimeStamp = lastTimeRewardApplicable(_rewardToken);

        // Apply mathematical integration on the parabolic equaltion(r = at2 + bt + c) with limit t1 to t2 to 
        // get the area under curve for reward rate vz timestamp graph.
        uint256 totalRewardTokensAccumuated = _calculateRewardsUsedInDuration(
            lastUpdateTimeStamp, 
            latestApplicableTimeStamp, 
            reward.coefficient_c
        );

        return reward.rewardPerTokenStored + (totalRewardTokensAccumuated * DENOMINATOR / (totalStaked()));
    }

    function getRewardLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    function earned(address _account, address _rewardToken) public view returns (uint256) {
        UserReward memory userReward = userRewards[_rewardToken][_account];
        return (
            (balanceOf(_account) * (rewardPerToken(_rewardToken) - userReward.userRewardPerTokenPaid))
                / (DENOMINATOR )
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
        _rewards = _rewards ; // to support small deciaml rewards

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

        uint256 currentTime = block.timestamp;
        uint256 newFinishTime = currentTime + duration;

        uint256 timeDiff = newFinishTime -  currentTime;
        uint256 timeSquareDiff = newFinishTime * newFinishTime - currentTime * currentTime;
        uint256 timeCubeDiff = newFinishTime * newFinishTime * newFinishTime 
            -  currentTime * currentTime * currentTime;

        if(block.timestamp < rewardInfo.periodFinish) {
            uint256 finishTime = rewardInfo.periodFinish;
            uint256 leftover = _calculateRewardsUsedInDuration(currentTime, finishTime, rewardInfo.coefficient_c);
            _rewards = _rewards + leftover;
        }
        
        rewardInfo.coefficient_c = (
            int256(_rewards)
            - int256(timeCubeDiff * coefficient_a /  DENOMINATOR) / 3
            - int256(timeSquareDiff * coefficient_b / DENOMINATOR) / 2
            ) * int256(DENOMINATOR) / int256(timeDiff);
        
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

    function _calculateRewardsUsedInDuration(uint256 _fromTimestamp, uint256 _toTimestamp, int256 _coefficient_c) internal view returns(uint256){
        uint256 timeDiff = _toTimestamp - _fromTimestamp; 
        uint256 timeSquareDiff = _toTimestamp * _toTimestamp - _fromTimestamp * _fromTimestamp; 
        uint256 timeCubeDiff = _toTimestamp * _toTimestamp * _toTimestamp 
            - _fromTimestamp * _fromTimestamp * _fromTimestamp;

        // Calculate Area under parabolic curve denoted by r = at^2 +bt + c using mathematical integration
        // limits will be from & to timestamps

        int256 rewardsAccumulated = int256(coefficient_a * timeCubeDiff / 3
            + coefficient_b * timeSquareDiff / 2)
            + _coefficient_c * int256(timeDiff);

        return uint256(rewardsAccumulated) / DENOMINATOR;
    }

    /* ======================== Admin Functions ===================================== */

    function setRewardQueuerStatus(address _rewardQueuer, bool status) external onlyOwner {
        isRewardQueuer[_rewardQueuer] = status;

        emit QueuerStatusUpdated(_rewardQueuer, status);
    }

}
