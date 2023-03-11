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
 * @param fund The total funds(excluding fees) staked by profiles.
 * @param stage Round stage.
 * 
 */
struct Stake2FollowData {
    uint256 fund;
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
    // The fee that will be charged in percentage.
    uint256 public i_fee;
    // The minimum claim possible.
    //uint256 immutable i_minClaim;
    // SafeERC20 to transfer tokens.
    using SafeERC20 for IERC20;

    // Mapping to store the data associated with a round indexed by the round ID
    mapping(string => Stake2FollowData) dataByRound;
    // Mapping to store the stake of a given profile per round
    mapping(string => mapping(address => uint256)) roundToprofileStake;
    // Mapping to store whether a given profile has claim the reward or not per round
    mapping(string => mapping(address => bool)) roundToProfileHasClaimed;

    // Events
    event stake2Follow__HubSet(address hub, address sender);
    event stake2Follow__MsigSet(address msig, address sender);

    //event stake2Follow__RoundOpen(
    //    string roundId
    //);

    event stake2Follow__ProfileStake(
        string roundId,
        address profileAddress,
        uint256 stake,
        uint256 fees,
        uint256 currentTotalStake
    );

    event stake2Follow__ProfileWithdrawn(
        string roundId,
        address profileAddress,
        uint256 fund,
        uint256 currentTotalStake
    );

    event stake2Follow__RoundFreeze(
        string roundId,
        uint256 fund
    );

    event stake2Follow__RoundClaim(
        string roundId,
        uint256 fund
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
    event stake2Follow_SetFee(uint256 fee);
    event stake2Follow__withdraw(uint256 balance);

    constructor(uint256 fee, address wMatic) {
        i_fee = fee;
        i_wMatic = wMatic;
        //i_minReward = 1E17;
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
        address profileAddress,
        uint32 fund
    ) external stopInEmergency onlyHub {
        // Check if the round stage
        require(
            dataByRound[roundId].stage == ROUND_STAGE.CLAIM,
            "Errors.stake2Follow__claim__RoundNotOpenForClaim(): Round not open for claim"
        );

        // Check the profile had staked
        require(
            roundToprofileStake[roundId][profileAddress] > 0,
            "Errors.stake2Follow_claim_ProfileNotStake(): Profile Not Stake"
        );

        // Check if the profile has already claimed
        require(
            !roundToProfileHasClaimed[roundId][profileAddress],
            "Errors.stake2Follow__claim__ProfileAlreadyClaimed): Profile already claimed"
        );

        // Check if there's enough budget to pay the reward
        require(
            dataByRound[roundId].fund >= fund,
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
        payCurrency(profileAddress, fund);

        // Update total fund
        dataByRound[roundId].fund -= fund;
        // Set the flag indicating that the profile has already claimed
        roundToProfileHasClaimed[roundId][profileAddress] = true;

        emit stake2Follow__ProfileClaim(
            roundId,
            profileAddress,
            fund,
            dataByRound[roundId].fund
        );

        if (dataByRound[roundId].fund == 0) {
            emit stake2Follow__PubFinished(roundId);
        }
    }

    /**
     * @dev Each participant stake the fund to the round.
     * @param fund The fund to stake.
     * @param roundId The ID of the round.
     * @param profileAddress The address of the profile that staking.
     */
    function profileStake(
        uint256 fund,
        string memory roundId,
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

        // Separate fund from fees.
        uint256 fees = (fund / (100 + i_fee)) * (i_fee);
        // Set totoal stake.
        dataByRound[roundId].fund += (fund - fees);
        // Set profile stake
        roundToprofileStake[roundId][profileAddress] = fund - fees;

        // Transfer funds to stake contract
        IERC20(i_wMatic).safeTransferFrom(
            profileAddress,
            address(this),
            fund
        );

        // transfer fees
        payCurrency(s_multisig, fees);

        emit stake2Follow__ProfileStake(
            roundId,
            profileAddress,
            fund,
            fees,
            dataByRound[roundId].fund
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
     * @dev Open the round.
     * @param roundId The ID of the round.
     */
    /*
    function roundOpen(
        string memory roundId
    ) external stopInEmergency onlyHub {
        // Check if the round ID is valid
        require(
            bytes(roundId).length != 0,
            "Errors.stake2Follow__roundOpen__InvalidRoundId(): Invalid round ID"
        );

        // Check round in open stage
        require(
            dataByRound[roundId].stage != ROUND_STAGE.OPEN,
            "Errors.stake2Follow__roundOpen_RoundAlreadyOpen(): Round is already Open"
        );

        dataByRound[roundId].stage = ROUND_STAGE.OPEN;

        emit stake2Follow__RoundOpen(
            roundId
        );
    }
    */

    /**
     * @dev Freeze the round.
     * @param roundId The ID of the round.
     */
    function roundFreeze(
        string memory roundId
    ) external stopInEmergency onlyHub {
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
    }

    /**
     * @dev open the round for claim.
     * @param roundId The ID of the round.
     */
    function roundClaim(
        string memory roundId
    ) external stopInEmergency onlyHub {
        // Check round in freeze stage
        require(
            dataByRound[roundId].stage == ROUND_STAGE.FREEZE,
            "Errors.stake2Follow__freeze_RoundNotFREEZE(): Round is not in FREEZE"
        );

        dataByRound[roundId].stage = ROUND_STAGE.CLAIM;

        emit stake2Follow__RoundClaim(
            roundId,
            dataByRound[roundId].fund
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
        // Get budget for this publication
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
    function setFee(uint256 fee) public onlyOwner {
        require(
            fee >= 0 && fee < 100,
            "Errors.stake2Follow__setFee_FeeInvalid(): Fee invalid"
        );
        i_fee = fee;
        emit stake2Follow_SetFee(fee);
    }

    /**
     * @dev Get fee
     */
    function getFee() public view returns (uint256) {
        return i_fee;
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

    /**
     * @dev Withdraws stake for a profile
     * @param roundId The ID of the round.
     * @param profileAddress The profile address.
     */
    function profileWithdraw(
        string memory roundId,
        address profileAddress
    ) public stopInEmergency {
        // Check roudId validity
        require(
            bytes(roundId).length != 0,
            "Errors.stake2Follow__withdraw__InvalidRoundId(): Invalid round Id"
        );

        // Check if the round is open
        require(
            dataByRound[roundId].stage == ROUND_STAGE.OPEN,
            "Errors.stake2Follow__withdraw__RoundNotOpen(): round not open"
        );

        // Check that the sender match profile
        require(
            profileAddress == msg.sender,
            "Errors.stake2Follow__withdraw__NotSenderProfileToWithdraw(): Withdrawer is not the profile"
        );

        // Check the profile is staked before
        require(
            roundToprofileStake[roundId][profileAddress] > 0,
            "Errors.stake2Follow__withdraw_ProfileNotStakedBefore(): profile not staked before"
        );

        // withdrow fund
        payCurrency(msg.sender, roundToprofileStake[roundId][profileAddress]);

        // update total fund
        dataByRound[roundId].fund -= roundToprofileStake[roundId][profileAddress];

        emit stake2Follow__ProfileWithdrawn(
            roundId, 
            msg.sender, 
            roundToprofileStake[roundId][profileAddress], 
            dataByRound[roundId].fund
        );
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