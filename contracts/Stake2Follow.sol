// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "OpenZeppelin/openzeppelin-contracts@4.5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@4.5.0/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@4.5.0/contracts/token/ERC721/IERC721.sol";

/**
 * @title Stake2Follow
 * @author atlasxu
 * @notice A contract to encourage follow on Lens Protocol by staking
 */


/**
 * stages of a Stake Round
 * 
 */
enum ROUND_STAGE {
    // Round is open, Allow profiles to stake
    OPEN,
    // Round is close, Allow profile to claim
    CLOSE
}

/**
 * @notice A struct containing stake round informations including total funds, stage etc.
 *
 * @param startTime round start time
 * @param freezeTime round freeze time, after freeze, no one can stake any more, and the round is calculating for close
 * @param fund Total funds.
 * @param qualify The qualify of profile to claim. last 8 bits is profile count; (8+n)-th bit is profile n's qualification
 * @param profiles profile addresses.
 * @param stage Round stage.
 * 
 */
struct Stake2FollowData {
    uint256 roundId;
    uint256 startTime;
    uint256 freezeTime;
    uint256 fund;
    uint256 qualify;
    address[] profiles;
    uint256[] profileIds;
    ROUND_STAGE stage;
}

contract stake2Follow {
    // Address of the deployer.
    address public owner;
    // The address of the multisig contract.
    address public s_multisig;
    // The addresses of whitelisted currencies.
    address private immutable i_wMatic;
    // Circuit breaker
    bool private stopped = false;
    // The address of hub contract.
    address public s_hub;
    // The minimum claim possible.
    //uint256 immutable i_minClaim;
    // SafeERC20 to transfer tokens.
    using SafeERC20 for IERC20;


    // stake amount of each profile
    uint256 public i_stakeValue;
    // The fee of gas
    uint256 public i_gasFee;
    // The fee of reward
    uint256 public i_rewardFee;

    // The maximum profiles of each round
    uint256 public i_maxProfiles;

    uint256 public currentRoundId;

    // Mapping to store the data associated with a round indexed by the round ID
    mapping(uint256 => Stake2FollowData) dataByRound;
    // Mapping to store the stake of a given profile per round
    mapping(uint256 => mapping(address => uint256)) roundToProfileReward;
    // Mapping to store whether a given profile has claim the reward or not per round
    //mapping(uint256 => mapping(uint256 => bool)) roundToProfileHasClaimed;

    uint256 public constant MIN_LENGTH_ROUND = 3 minutes;
    uint256 public constant MAX_LENGTH_ROUND = 1 days + 5 minutes;

    // Events
    event stake2Follow__HubSet(address hub, address sender);
    event stake2Follow__MsigSet(address msig, address sender);

    event stake2Follow__ProfileStake(
        uint256 roundId,
        address profileAddress,
        uint256 stake,
        uint256 fees,
        uint256 profiles
    );

    event stake2Follow__RoundStart(
        uint256 roundId,
        uint256 startTime,
        uint256 endTime
    );
    event stake2Follow__RoundFreeze(
        uint256 roundId,
        uint256 fund
    );

    event stake2Follow__RoundClaim(
        uint256 roundId,
        uint256 reward,
        uint256 rewardFee,
        uint256 totalProfiles,
        uint256 qualifyProfiles
    );

    event stake2Follow__ProfileClaim(
        uint256 roundId,
        address profileAddress,
        uint256 fund,
        uint256 remainingFund
    );

    event stake2Follow__CircuitBreak(bool stop);

    event stake2Follow__EmergencyWithdraw(
        uint256 roundId,
        uint256 fund,
        address sender
    );
    event stake2Follow__SetGasFee(uint256 fee);
    event stake2Follow__SetRewardFee(uint256 fee);
    event stake2Follow__SetMaxProfiles(uint256 profiles);
    event stake2Follow__SetStakeValue(uint256 value);
    event stake2Follow__withdraw(uint256 balance);

    constructor(uint256 stakeValue, uint256 gasFee, uint256 rewardFee, uint8 maxProfiles, address wMatic) {
        i_gasFee = gasFee;
        i_rewardFee = rewardFee;
        i_wMatic = wMatic;
        //i_minReward = 1E17;
        i_stakeValue = stakeValue;
        i_maxProfiles = maxProfiles;
        currentRoundId = 0;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function.");
        _;
    }

    modifier onlyHub() {
        require(
            msg.sender == s_hub,
            "Errors.Only hub can call this function."
        );
        _;
    }

    modifier stopInEmergency() {
        require(
            !stopped,
            "Emergency stop is active, function execution is prevented."
        );
        _;
    }
    modifier onlyInEmergency() {
        require(stopped, "Not in Emergency, function execution is prevented.");
        _;
    }

    /**
     * @dev Transfer fund to profile
     * @param profileAddress The address of the profile
     */
    function profileClaim(
        address profileAddress
    ) external stopInEmergency onlyHub {
        // Check if the round stage
        require(
            dataByRound[currentRoundId].stage == ROUND_STAGE.CLOSE,
            "Errors.stake2Follow__claim__RoundNotClose(): Round not close to claim"
        );

        // TODO: check the profile has qualify to claim
        // Here we don't do this cause if profile is not qualified, then no value can be claimed
        // (see following check)

        // Check the profile has value to claim
        require(
            roundToProfileReward[currentRoundId][profileAddress] > 0,
            "Errors.stake2Follow_claim_ProfileNotStake(): Profile has no value to claim"
        );

        // Check if there's enough budget to pay the reward
        require(
            dataByRound[currentRoundId].fund >= roundToProfileReward[currentRoundId][profileAddress],
            "Errors.stake2Follow__claim__NotEnoughFundForThatClaim): Not enough fund for the specified claim"
        );

        // Check if the profile address is valid
        require(
            profileAddress != address(0),
            "Errors.stake2Follow__claim__InvalidProfileAddress(): Invalid profile address"
        );

        // Transfer the fund to profile
        payCurrency(profileAddress, roundToProfileReward[currentRoundId][profileAddress]);
        // Set the flag indicating that the profile has already claimed
        roundToProfileReward[currentRoundId][profileAddress] = 0;
        // Update total fund
        dataByRound[currentRoundId].fund -= roundToProfileReward[currentRoundId][profileAddress];

        emit stake2Follow__ProfileClaim(
            currentRoundId,
            profileAddress,
            roundToProfileReward[currentRoundId][profileAddress],
            dataByRound[currentRoundId].fund
        );
    }

    /**
     * @dev Each participant stake the fund to the round.
     * @param profileId The ID of len profile.
     * @param profileAddress The address of the profile that staking.
     */
    function profileStake(
        uint256 profileId,
        address profileAddress
    ) external stopInEmergency {
        // Check if the msg.sender is the profile owner
        require(
            msg.sender == profileAddress,
            "Errors.stake2Follow__stake__SenderNotOwner(): Sender is not the profile owner"
        );

        // Check if the profile address is valid
        require(
            profileAddress != address(0),
            "Errors.stake2Follow__stake__InvalidProfileAddress(): Invalid profile address"
        );

        // Check round is in open stage
        require(
            dataByRound[currentRoundId].stage == ROUND_STAGE.OPEN,
            "Errors.stake2Follow__stake__RoundNotOpen(): Round is not in open stage"
        );

        // check round end time
        require(
            block.timestamp < dataByRound[currentRoundId].freezeTime,
            "Errors.stake2Follow__stake__RoundIsNotOpen(): Round is not open"
        );

        // Check profile count
        require(
            dataByRound[currentRoundId].profiles.length < i_maxProfiles,
            "Errors.stake2Follow__stake__ExceedMaximumProfileLimit(): Maximum profile limit reached"
        );

        // Calculate fee
        uint256 stakeFee = (i_stakeValue / 100) * i_gasFee;

        // Transfer funds to stake contract
        IERC20(i_wMatic).safeTransferFrom(
            profileAddress,
            address(this),
            i_stakeValue + stakeFee
        );

        // transfer fees
        payCurrency(s_multisig, stakeFee);

        // Set totoal stake.
        dataByRound[currentRoundId].fund += i_stakeValue;

        // add profile
        dataByRound[currentRoundId].profiles.push(profileAddress);
        dataByRound[currentRoundId].profileIds.push(profileId);

        emit stake2Follow__ProfileStake(
            currentRoundId,
            profileAddress,
            i_stakeValue,
            stakeFee,
            dataByRound[currentRoundId].profiles.length
        );
    }

    function payCurrency(address to, uint256 amount) internal {
        require(
            amount > 0,
            "Errors.stake2Follow__pay__InvalidPay(): Invalid amount"
        );

        IERC20(i_wMatic).safeTransfer(
            to,
            amount
        );
    }

    /**
     * @dev start the round.
     * @param freezeTime The time round freeze.
     */
    function openRound(
        uint256 freezeTime
    ) external stopInEmergency onlyHub {
        // Check last round is in claim stage
        // only one round can be started at same time
        require(
            (currentRoundId == 0) || (dataByRound[currentRoundId].stage == ROUND_STAGE.CLOSE),
            "Errors.stake2Follow__start__LastRoundNotFinish(): Last Round is not finish"
        );

        // Check round length
        require(
            ((freezeTime - block.timestamp) > MIN_LENGTH_ROUND) && ((freezeTime - block.timestamp) < MAX_LENGTH_ROUND),
            "Errors.stake2Follow__start__RoundLengthOutOfRange(): Round length out of range"
        );

        // update current round
        currentRoundId++;

        // mark round to open
        dataByRound[currentRoundId].roundId = currentRoundId;
        dataByRound[currentRoundId].stage = ROUND_STAGE.OPEN;
        dataByRound[currentRoundId].startTime = block.timestamp;
        dataByRound[currentRoundId].freezeTime = freezeTime;


        emit stake2Follow__RoundStart(
            currentRoundId,
            block.timestamp,
            freezeTime
        );
    }

    /**
     * @dev close the round.
     * @param qualifies Bit array to indicate profile qualification of claim
     */
    function closeRound(
        uint256 qualifies
    ) external stopInEmergency onlyHub {
        // Check round in open stage
        require(
            dataByRound[currentRoundId].stage == ROUND_STAGE.OPEN,
            "Errors.stake2Follow__claim__RoundNotOpen(): Round is not in OPEN"
        );

        // round is end
        require(
            block.timestamp > dataByRound[currentRoundId].freezeTime,
            "Errors.stake2Follow__claim__RoundNotEnd(): Round is not freeze, only freeze round can be close"
        );

        uint256 profileNum = dataByRound[currentRoundId].profiles.length;
        // first 8-bit records how many qualifies
        uint256 qualifyNum = qualifies & 255;
        require(
            profileNum >= qualifyNum,
            "Errors.stake2Follow__claim__qualifyNumInvalid(): qualify profiles > totoal profiles"
        );

        // calculate reward
        uint256 reward = i_stakeValue * (profileNum - qualifyNum);
        uint256 rewardFee = (reward / 100) * i_rewardFee;
        uint256 avgReward = (reward - rewardFee) / qualifyNum;

        uint256 qualifyNum2 = 0;
        for (uint i = 0; i < profileNum; i++) {
            // get i-th bit of qualifies
            uint qualify = (qualifies >> (i + 8)) & 1;
            roundToProfileReward[currentRoundId][dataByRound[currentRoundId].profiles[i]] = (i_stakeValue + avgReward) * qualify;

            qualifyNum2 += qualify;
        }

        require(
            qualifyNum == qualifyNum2,
            "Errors.stake2Follow__claim__qualifies_bit_invalid(): qualifies bit array invalid"
        );

        // transfer fees
        if (rewardFee > 0) {
            payCurrency(s_multisig, rewardFee);
            dataByRound[currentRoundId].fund -= rewardFee;
        }

        // record
        dataByRound[currentRoundId].qualify = qualifies;

        dataByRound[currentRoundId].stage = ROUND_STAGE.CLOSE;

        emit stake2Follow__RoundClaim(
            currentRoundId,
            reward,
            rewardFee,
            profileNum,
            qualifyNum
        );
    }

    /**
     * @dev Gets the fund for a round.
     * @return The fund for the round.
     */
    function getRoundFund() public view returns (uint256) {
        // Get fund for this round
        return dataByRound[currentRoundId].fund;
    }

    function getRoundData() public view returns (Stake2FollowData memory) {
        return dataByRound[currentRoundId];
    }

    /**
     * @dev Sets the hub address. This can only be called by the contract owner.
     * @param hub The hub address.
     */
    function setHub(address hub) public onlyOwner {
        s_hub = hub;
        emit stake2Follow__HubSet(hub, msg.sender);
    }

    function getHub() public view returns (address) {
        return s_hub;
    }

    /**
     * @dev Sets the fee percentage
     * @param fee fee in percentage
     */
    function setGasFee(uint256 fee) public onlyOwner {
        require(
            fee < 100,
            "Errors.stake2Follow__setFee_FeeInvalid(): Fee invalid"
        );
        i_gasFee = fee;
        emit stake2Follow__SetGasFee(fee);
    }

    /**
     * @dev Get fee
     */
    function getGasFee() public view returns (uint256) {
        return i_gasFee;
    }

    /**
     * @dev Sets the fee percentage
     * @param fee fee in percentage
     */
    function setRewardFee(uint256 fee) public onlyOwner {
        require(
            fee < 100,
            "Errors.stake2Follow__setFee_FeeInvalid(): Fee invalid"
        );
        i_rewardFee = fee;
        emit stake2Follow__SetRewardFee(fee);
    }

    /**
     * @dev Get fee
     */
    function getRewardFee() public view returns (uint256) {
        return i_rewardFee;
    }

    /**
     * @dev Sets the stake value
     * @param stakeValue stake value
     */
    function setStakeValue(uint256 stakeValue) public onlyOwner {
        require(
            stakeValue < 10000,
            "Errors.stake2Follow__setStakeValue_ParaInvalid(): Param invalid"
        );

        i_stakeValue = stakeValue;
        emit stake2Follow__SetStakeValue(stakeValue);
    }

    /**
     * @dev Get stake value
     */
    function getStakeValue() public view returns (uint256) {
        return i_stakeValue;
    }

    /**
     * @dev Sets the max allowed profile count in a round
     * @param profiles max profiles count
     */
    function setMaxProfiles(uint256 profiles) public onlyOwner {
        require(
            profiles < 248,
            "Errors.stake2Follow__setMaxProfiles_ParaInvalid(): Param invalid"
        );
        i_maxProfiles = profiles;
        emit stake2Follow__SetMaxProfiles(profiles);
    }

    /**
     * @dev Get max allowed profile count in a round
     */
    function getMaxProfiles() public view returns (uint256) {
        return i_maxProfiles;
    }

    /**
     * @dev Sets the multisig address. This can only be called by the contract owner.
     * @param multisig The new multisig address.
     */
    function setMultisig(address multisig) public onlyOwner {
        s_multisig = multisig;
        emit stake2Follow__MsigSet(multisig, msg.sender);
    }

    function getMultisig() public view returns (address) {
        return s_multisig;
    }

    function isRoundOpen() public view returns (bool) {
        return ((dataByRound[currentRoundId].stage == ROUND_STAGE.OPEN) && (block.timestamp <= dataByRound[currentRoundId].freezeTime));
    }

    function isRoundFreeze() public view returns (bool) {
        return ((dataByRound[currentRoundId].stage == ROUND_STAGE.OPEN) && (block.timestamp > dataByRound[currentRoundId].freezeTime));
    }

    function isRoundClose() public view returns (bool) {
        return (dataByRound[currentRoundId].stage == ROUND_STAGE.CLOSE);
    }

    function circuitBreaker() public onlyOwner {
        stopped = !stopped;
        emit stake2Follow__CircuitBreak(stopped);
    }

    function withdrawRound() public onlyInEmergency onlyHub {
        // Check round stage
        require(
            dataByRound[currentRoundId].stage != ROUND_STAGE.OPEN,
            "Errors.stake2Follow__EmergencyWithdraw__RoundIsOpen(): Round is Open"
        );

        // Check that there is enough funds to withdraw
        require(
            dataByRound[currentRoundId].fund > 0,
            "Errors.stake2Follow__EmergencyWithdraw__NotEnoughFundToWithdraw(): The fund is empty"
        );

        // withdraw to hub address
        payCurrency(msg.sender, dataByRound[currentRoundId].fund);

        emit stake2Follow__EmergencyWithdraw(
            currentRoundId,
            dataByRound[currentRoundId].fund,
            msg.sender
        );
        dataByRound[currentRoundId].fund = 0;
    }

    function withdraw() public onlyInEmergency onlyOwner {
        uint256 balance = IERC20(i_wMatic).balanceOf(address(this));
        // Check that there is enough funds to withdraw
        require(
            balance > 0,
            "Errors.stake2Follow__EmergencyWithdraw__NotEnoughFundToWithdraw(): The fund is empty"
        );

        payCurrency(msg.sender, balance);
        emit stake2Follow__withdraw(balance);
    }

    /** @notice To be able to pay and fallback
     */
    receive() external payable {}

    fallback() external payable {}
}