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
    // SafeERC20 to transfer tokens.
    using SafeERC20 for IERC20;

    // genesis time
    uint256 genesis;

    // stake amount of each profile
    uint256 public i_stakeValue;
    // The fee of gas
    uint256 public i_gasFee;
    // The fee of reward
    uint256 public i_rewardFee;

    // The maximum profiles of each round
    uint256 public i_maxProfiles;

    // roundId => qualify info
    // qualify bits    claimed bits    claimable
    //  [0 --- 99]    [ 100 ------199]   [200]
    mapping(uint256 => uint256) roundToQualify;

    // roundId => reward
    mapping(uint256 => uint256) roundToReward;

    /// roundId => profiles
    mapping(uint256 => uint256[]) roundToProfiles;

    // profiles => roundIds
    mapping(uint256 => uint256[]) profileToRounds;

    // profileId -> address
    mapping(uint256 => address) profileToAddress;

    // uint256 public constant MAXIMAL_PROFILES = 100;
    // uint256 public constant ROUND_OPEN_LENGTH = 60 minutes;
    // uint256 public constant ROUND_FREEZE_LENGTH = 30 minutes;
    // uint256 public constant ROUND_GAP_LENGTH = 120 minutes;

    uint256 public constant MAXIMAL_PROFILES = 5;
    uint256 public constant ROUND_OPEN_LENGTH = 5 minutes;
    uint256 public constant ROUND_FREEZE_LENGTH = 5 minutes;
    uint256 public constant ROUND_GAP_LENGTH = 15 minutes;

    // Events
    event stake2Follow__HubSet(address hub, address sender);
    event stake2Follow__MsigSet(address msig, address sender);

    event stake2Follow__ProfileStake(
        uint256 roundId,
        address profileAddress,
        uint256 stake,
        uint256 fees
    );

    event stake2Follow__ClaimbleRound(
        uint256 roundId,
        uint256 reward,
        uint256 totalProfiles,
        uint256 qualifyProfiles
    );

    event stake2Follow__ProfileClaim(
        uint256 roundId,
        uint256 profileId,
        uint256 fund
    );

    event stake2Follow__ProfileExclude(
        uint256 roundId,
        uint256 qualifies
    );

    event stake2Follow__CircuitBreak(bool stop);
    event stake2Follow__SetGasFee(uint256 fee);
    event stake2Follow__SetRewardFee(uint256 fee);
    event stake2Follow__SetMaxProfiles(uint256 profiles);
    event stake2Follow__SetStakeValue(uint256 value);
    event stake2Follow__Withdraw(uint256 balance);

    constructor(uint256 stakeValue, uint256 gasFee, uint256 rewardFee, uint8 maxProfiles, address wMatic) {
        genesis = block.timestamp;

        i_gasFee = gasFee;
        i_rewardFee = rewardFee;
        i_wMatic = wMatic;
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
     * @param profileIndex The index in the profiles array
     */
    function profileClaim(
        uint256 roundId,
        uint256 profileIndex
    ) external stopInEmergency onlyHub {
        uint256 startTime = genesis + roundId * ROUND_GAP_LENGTH;
        // ensure round is after freeze time
        require(
            (block.timestamp - startTime) > (ROUND_OPEN_LENGTH + ROUND_FREEZE_LENGTH),
            "Errors.stake2Follow__claim__RoundIsNotOver(): Round is not over"
        );

        // ensure round is claimble
        require(
            ((roundToQualify[roundId] >> 200) & 1) == 1,
            "Errors.stake2Follow__claim__RoundNotClose(): Round not ready to claim"
        );

        // out-of-bound check
        require(
            profileIndex < roundToProfiles[roundId].length,
            "Errors.stake2Follow__claim__ProfileIndexOutOfBound(): index out of bound"
        );

        uint256 profileId = roundToProfiles[roundId][profileIndex];

        // check address legal
        require(
            msg.sender == profileToAddress[profileId],
            "Errors.stake2Follow__claim__AddessNotMatchProfile(): Address not match profile"
        );

        // Check the profile has qualify to claim
        require(
             ((roundToQualify[roundId] >> profileIndex) & 1) == 1,
            "Errors.stake2Follow__claim__ProfileNotQualify(): Profile not qualify to claimed"
        );

        // Check the profile has not claimed
        require(
             ((roundToQualify[roundId] >> (profileIndex + 100)) & 1) == 0,
            "Errors.stake2Follow__claim__ProfileAlreadyClaimed(): Profile already claimed"
        );

        // check reward
        require(
            roundToReward[roundId] > 0,
            "Errors.stake2Follow_claim_RewardIsZero(): Reward is illegal"
        );

        // Transfer the fund to profile
        payCurrency(profileToAddress[profileId], roundToReward[roundId]);
        
        // Set the flag indicating that the profile has already claimed
        roundToQualify[roundId] |= (1 << (100 + profileIndex));

        emit stake2Follow__ProfileClaim(
            roundId,
            profileId,
            roundToReward[roundId]
        );
    }

    /**
     * @dev Each participant stake the fund to the round.
     * @param roundId the round id.
     * @param profileId The ID of len profile.
     * @param profileAddress The address of the profile that staking.
     */
    function profileStake(
        uint256 roundId,
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

        uint256 startTime = genesis + roundId * ROUND_GAP_LENGTH;

        // Check round is in open stage
        require(
            block.timestamp > startTime && block.timestamp < (startTime + ROUND_OPEN_LENGTH),
            "Errors.stake2Follow__stake__RoundNotOpen(): Round is not in open stage"
        );

        // Check profile count
        require(
            roundToProfiles[roundId].length < i_maxProfiles,
            "Errors.stake2Follow__stake__ExceedMaximumProfileLimit(): Maximum profile limit reached"
        );

        // bind address to profile
        profileToAddress[profileId] = profileAddress;

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

        // add profile
        roundToProfiles[roundId].push(profileId);

        // add round
        profileToRounds[profileId].push(roundId);

        emit stake2Follow__ProfileStake(
            roundId,
            profileAddress,
            i_stakeValue,
            stakeFee
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
     * @dev make round claimble
     * @param qualifies Bit array to indicate profile qualification of claim
     */
    function claimbleRound(
        uint256 roundId,
        uint256 qualifies
    ) external stopInEmergency onlyHub {
        uint256 startTime = genesis + roundId * ROUND_GAP_LENGTH;
        // ensure round is after freeze time
        require(
            (block.timestamp - startTime) > (ROUND_OPEN_LENGTH + ROUND_FREEZE_LENGTH),
            "Errors.stake2Follow__claim__RoundIsNotOver(): Round is not over"
        );

        uint256 profileNum = roundToProfiles[roundId].length;
        // get how many qualifies
        uint256 qualifyNum = 0;
        for (uint256 i = 0; i < profileNum; i++) {
            qualifyNum += ((qualifies >> i) & 1);
        }

        require(
            profileNum >= qualifyNum,
            "Errors.stake2Follow__claim__ClaimbleRound(): bad qualifies input"
        );

        // calculate reward
        if (qualifyNum == profileNum) {
            roundToReward[roundId] = i_stakeValue;
        } else {
            uint256 reward = i_stakeValue * (profileNum - qualifyNum);
            uint256 rewardFee = (reward / 100) * i_rewardFee;

            roundToReward[roundId] = i_stakeValue + ((reward - rewardFee) / qualifyNum);

            // transfer fees
            payCurrency(s_multisig, rewardFee);
        }

        // record
        roundToQualify[roundId] |= qualifies;

        emit stake2Follow__ClaimbleRound(
            roundId,
            roundToReward[roundId],
            profileNum,
            qualifyNum
        );
    }

    /**
     * @dev exclude profiles which is illegal
     * @param roundId current round id
     * @param illegals Bit array to indicate profile qualification of claim
     */
    function profileExclude(
        uint256 roundId,
        uint256 illegals
    ) external stopInEmergency onlyHub {
        // ensure round is not claimble
        require(
            ((roundToQualify[roundId] >> 200) & 1) == 0,
            "Errors.stake2Follow__profileExclude__RoundIsClose(): Round is finish"
        );

        uint256 profileNum = roundToProfiles[roundId].length;
        uint256 illegalNum = 0;
        for (uint256 i = 0; i < profileNum; i++) {
            illegalNum += ((illegals >> i) & 1);
        }

        require(
            profileNum >= illegalNum,
            "Errors.stake2Follow__profileExclude__profileExclude(): bad illegals input"
        );

        roundToQualify[roundId] |= (illegals << 100);

        emit stake2Follow__ProfileExclude(roundId, roundToQualify[roundId]);
    }

    function getRoundData(uint256 roundId) public view returns (uint256 qualify, uint256 reward, uint256[] memory profiles) {
        return (roundToQualify[roundId], roundToReward[roundId], roundToProfiles[roundId]);
    }

    function getProfileRounds(uint256 profileId) public view returns (uint256[] memory roundIds) {
        return profileToRounds[profileId];
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
            profiles <= MAXIMAL_PROFILES,
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

    function getConfig() public view returns (
        uint256 stakeValue, 
        uint256 gasFee, 
        uint256 rewardFee, 
        uint256 maxProfiles,
        uint256 genesis,
        uint256 roundOpenLength,
        uint256 roundFreezeLength,
        uint256 roundGapLength
        ) {
        return (i_stakeValue, i_gasFee, i_rewardFee, i_maxProfiles, genesis, ROUND_OPEN_LENGTH, ROUND_FREEZE_LENGTH, ROUND_GAP_LENGTH);
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

    function getCurrentRound() public view returns (uint256 roundId, uint256 startTime) {
        uint256 crrentRoundId = (block.timestamp - genesis) / ROUND_GAP_LENGTH;
        return (crrentRoundId, genesis + crrentRoundId * ROUND_GAP_LENGTH);
    }

    function circuitBreaker() public onlyOwner {
        stopped = !stopped;
        emit stake2Follow__CircuitBreak(stopped);
    }

    function withdraw() public onlyInEmergency onlyOwner {
        uint256 balance = IERC20(i_wMatic).balanceOf(address(this));
        // Check that there is enough funds to withdraw
        require(
            balance > 0,
            "Errors.stake2Follow__EmergencyWithdraw__NotEnoughFundToWithdraw(): The fund is empty"
        );

        payCurrency(msg.sender, balance);
        emit stake2Follow__Withdraw(balance);
    }

    /** @notice To be able to pay and fallback
     */
    receive() external payable {}

    fallback() external payable {}
}