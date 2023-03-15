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
 * 3 stages of a Stake Round
 * 
 */
enum ROUND_STAGE {
    // Allow profiles to stake
    OPEN,
    // Task time, before freeze stage finish, will calculate the reward of each profile
    FREEZE,
    // Allow profile to claim fund
    CLAIM
}

/**
 * @notice A struct containing stake round informations including total funds, stage etc.
 *
 * @param fund Total funds.
 * @param qualify The qualify of profile to claim. last 8 bits is profile count; (8+n)-th bit is profile n's qualification
 * @param profiles profile addresses.
 * @param stage Round stage.
 * 
 */
struct Stake2FollowData {
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

    // Mapping to store the data associated with a round indexed by the round ID
    mapping(string => Stake2FollowData) dataByRound;
    // Mapping to store the stake of a given profile per round
    mapping(string => mapping(address => uint256)) roundToProfileReward;
    // Mapping to store whether a given profile has claim the reward or not per round
    //mapping(string => mapping(address => bool)) roundToProfileHasClaimed;

    // Events
    event stake2Follow__HubSet(address hub, address sender);
    event stake2Follow__MsigSet(address msig, address sender);

    event stake2Follow__ProfileStake(
        string roundId,
        address profileAddress,
        uint256 stake,
        uint256 fees,
        uint256 profiles
    );

    event stake2Follow__RoundFreeze(
        string roundId,
        uint256 fund
    );

    event stake2Follow__RoundClaim(
        string roundId,
        uint256 reward,
        uint256 rewardFee,
        uint256 totalProfiles,
        uint256 qualifyProfiles
    );

    event stake2Follow__ProfileClaim(
        string roundId,
        address profileAddress,
        uint256 fund,
        uint256 remainingFund
    );
    event stake2Follow__PubFinished(string roundId);

    event stake2Follow__CircuitBreak(bool stop);

    event stake2Follow__EmergencyWithdraw(
        string roundId,
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
     * @param roundId The ID of the round.
     * @param profileAddress The address of the profile
     */
    function profileClaim(
        string memory roundId,
        address profileAddress
    ) external stopInEmergency onlyHub {
        // Check if the round stage
        require(
            dataByRound[roundId].stage == ROUND_STAGE.CLAIM,
            "Errors.stake2Follow__claim__RoundNotOpenForClaim(): Round not open for claim"
        );

        // TODO: check the profile has qualify to claim
        // Here we don't do this cause if profile is not qualified, then no value can be claimed
        // (see following check)

        // Check the profile has value to claim
        require(
            roundToProfileReward[roundId][profileAddress] > 0,
            "Errors.stake2Follow_claim_ProfileNotStake(): Profile has no value to claim"
        );

        // Check if there's enough budget to pay the reward
        require(
            dataByRound[roundId].fund >= roundToProfileReward[roundId][profileAddress],
            "Errors.stake2Follow__claim__NotEnoughFundForThatClaim): Not enough fund for the specified claim"
        );

        // Check if the profile address is valid
        require(
            profileAddress != address(0),
            "Errors.stake2Follow__claim__InvalidProfileAddress(): Invalid profile address"
        );

        // Check if the round ID is valid
        require(
            bytes(roundId).length != 0,
            "Errors.stake2Follow__claim__InvalidRoundId(): Invalid round ID"
        );

        // Transfer the fund to profile
        payCurrency(profileAddress, roundToProfileReward[roundId][profileAddress]);
        // Update total fund
        dataByRound[roundId].fund -= roundToProfileReward[roundId][profileAddress];

        emit stake2Follow__ProfileClaim(
            roundId,
            profileAddress,
            roundToProfileReward[roundId][profileAddress],
            dataByRound[roundId].fund
        );

        // Set the flag indicating that the profile has already claimed
        roundToProfileReward[roundId][profileAddress] = 0;

        if (dataByRound[roundId].fund == 0) {
            emit stake2Follow__PubFinished(roundId);
        }
    }

    /**
     * @dev Each participant stake the fund to the round.
     * @param roundId The ID of the round.
     * @param profileId The ID of len profile.
     * @param profileAddress The address of the profile that staking.
     */
    function profileStake(
        string memory roundId,
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
        // Check if the round ID is valid
        require(
            bytes(roundId).length != 0,
            "Errors.stake2Follow__stake__InvalidRoundId(): Invalid round ID"
        );

        // Check round is in open stage
        require(
            dataByRound[roundId].stage == ROUND_STAGE.OPEN,
            "Errors.stake2Follow__stake__RoundNotOpen(): Round is not in open stage"
        );

        // Check profile count
        require(
            dataByRound[roundId].profiles.length < i_maxProfiles,
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
        dataByRound[roundId].fund += i_stakeValue;

        // add profile
        dataByRound[roundId].profiles.push(profileAddress);
        dataByRound[roundId].profileIds.push(profileId);

        emit stake2Follow__ProfileStake(
            roundId,
            profileAddress,
            i_stakeValue,
            stakeFee,
            dataByRound[roundId].profiles.length
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
     * @dev Freeze the round.
     * @param roundId The ID of the round.
     * @return round data
     */
    function roundFreeze(
        string memory roundId
    ) external stopInEmergency onlyHub returns (Stake2FollowData memory) {
        // Check round has fund
        require(
            dataByRound[roundId].fund > 0,
            "Errors.stake2Follow__freeze_RoundHasNoFund(): Round has no fund"
        );

        // Check round in open stage
        require(
            dataByRound[roundId].stage == ROUND_STAGE.OPEN,
            "Errors.stake2Follow__freeze_RoundNotOpen(): Round is not Open"
        );

        dataByRound[roundId].stage = ROUND_STAGE.FREEZE;

        emit stake2Follow__RoundFreeze(
            roundId,
            dataByRound[roundId].fund
        );

        return dataByRound[roundId];
    }


    /**
     * @dev open the round for claim.
     * @param roundId The ID of the round.
     * @param qualifies Bit array to indicate profile qualification of claim
     */
    function roundClaim(
        string memory roundId,
        uint256 qualifies
    ) external stopInEmergency onlyHub {
        // Check round in freeze stage
        require(
            dataByRound[roundId].stage == ROUND_STAGE.FREEZE,
            "Errors.stake2Follow__claim__RoundNotFREEZE(): Round is not in FREEZE"
        );

        uint256 profileNum = dataByRound[roundId].profiles.length;
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
            roundToProfileReward[roundId][dataByRound[roundId].profiles[i]] = (i_stakeValue + avgReward) * qualify;

            qualifyNum2 += qualify;
        }

        require(
            qualifyNum == qualifyNum2,
            "Errors.stake2Follow__claim__qualifies_bit_invalid(): qualifies bit array invalid"
        );

        // transfer fees
        if (rewardFee > 0) {
            payCurrency(s_multisig, rewardFee);
            dataByRound[roundId].fund -= rewardFee;
        }

        // record
        dataByRound[roundId].qualify = qualifies;

        dataByRound[roundId].stage = ROUND_STAGE.CLAIM;

        emit stake2Follow__RoundClaim(
            roundId,
            reward,
            rewardFee,
            profileNum,
            qualifyNum
        );
    }

    /**
     * @dev Gets the fund for a round.
     * @param roundId The ID of the round.
     * @return The fund for the round.
     */
    function getRoundFund(
        string memory roundId
    ) public view returns (uint256) {
        // Get fund for this round
        return dataByRound[roundId].fund;
    }

    function getRoundData(
        string memory roundId
    ) public view returns (Stake2FollowData memory) {
        return dataByRound[roundId];
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

    function isRoundOpen(string memory roundId) public view returns (bool) {
        return dataByRound[roundId].stage == ROUND_STAGE.OPEN;
    }

    function isRoundFreeze(string memory roundId) public view returns (bool) {
        return dataByRound[roundId].stage == ROUND_STAGE.FREEZE;
    }

    function isRoundClaim(string memory roundId) public view returns (bool) {
        return dataByRound[roundId].stage == ROUND_STAGE.CLAIM;
    }

    function circuitBreaker() public onlyOwner {
        stopped = !stopped;
        emit stake2Follow__CircuitBreak(stopped);
    }

    function withdrawRound(
        string memory roundId
    ) public onlyInEmergency onlyHub {
        // Check roundid validity
        require(
            bytes(roundId).length != 0,
            "Errors.stake2Follow__EmergencyWithdraw__InvalidRoundId(): Invalid RoundId"
        );

        // Check round stage
        require(
            dataByRound[roundId].stage != ROUND_STAGE.OPEN,
            "Errors.stake2Follow__EmergencyWithdraw__RoundIsOpen(): Round is Open"
        );

        // Check that there is enough funds to withdraw
        require(
            dataByRound[roundId].fund > 0,
            "Errors.stake2Follow__EmergencyWithdraw__NotEnoughFundToWithdraw(): The fund is empty"
        );

        // withdraw to hub address
        payCurrency(msg.sender, dataByRound[roundId].fund);

        emit stake2Follow__EmergencyWithdraw(
            roundId,
            dataByRound[roundId].fund,
            msg.sender
        );
        dataByRound[roundId].fund = 0;
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