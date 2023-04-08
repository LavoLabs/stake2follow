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
    using SafeERC20 for IERC20;

    address public owner;
    address public walletAddress;
    address public appAddress;
    bool private stopped = false;
    IERC20 public currency;

    // contract deployed time
    uint256 genesis;
    // stake amount of each profile at each round
    uint256 public stakeValue;
    // The fee of stake, n/1000
    uint256 public gasFee;
    // The fee of reward, n/1000
    uint256 public rewardFee;
    // The maximum profiles of each round
    uint256 public maxProfiles;

    // First N profiles free of fee in each round
    uint256 public firstNFree = 0;

    // roundId => qualify info
    // qualify-bits   exclude-bits   claimed bits
    //  [0 --- 49]    [50------99]  [100------149]
    mapping(uint256 => uint256) roundToQualify;

    /// roundId => profiles
    mapping(uint256 => uint256[]) roundToProfiles;

    // profiles => roundIds
    mapping(uint256 => uint256[]) profileToRounds;

    // profileId -> address
    mapping(uint256 => address) profileToAddress;

    // share reward weight = profilesInvited
    mapping(uint256 => mapping(uint256 => uint256)) inviteBonus;

    // portation that shares to profiles invites people in. n/1000
    uint256 public inviteFee = 200;

    uint256 public constant MAXIMAL_PROFILES = 50;

    // uint256 public constant ROUND_OPEN_LENGTH = 3 hours;
    // uint256 public constant ROUND_FREEZE_LENGTH = 50 minutes;
    // uint256 public constant ROUND_GAP_LENGTH = 4 hours;
    uint256 public constant ROUND_OPEN_LENGTH = 10 minutes;
    uint256 public constant ROUND_FREEZE_LENGTH = 5 minutes;
    uint256 public constant ROUND_GAP_LENGTH = 18 minutes;

    // Events
    event ProfileStake(uint256 roundId, address profileAddress, uint256 stake, uint256 fees, uint256 refId);
    event ProfileQualify(uint256 roundId, uint256 qualify);
    event ProfileExclude(uint256 roundId, uint256 exclude);
    event ProfileClaim(uint256 roundId, uint256 profileId, uint256 fund);
    event AppSet(address app, address sender);
    event WalletSet(address wallet, address sender);
    event CircuitBreak(bool stop);
    event SetGasFee(uint256 fee);
    event SetRewardFee(uint256 fee);
    event SetMaxProfiles(uint256 profiles);
    event SetStakeValue(uint256 value);
    event SetFirstNFree(uint256 n);
    event SetInviteFee(uint256 n);
    event WithdrawRoundFee(uint256 roundId, uint256 fee);
    event Withdraw(uint256 balance);

    constructor(uint256 _stakeValue, uint256 _gasFee, uint256 _rewardFee, uint8 _maxProfiles, address _currency, address _appAddress, address _walletAddress) {
        currency = IERC20(_currency);

        gasFee = _gasFee;
        rewardFee = _rewardFee;
        stakeValue = _stakeValue;
        maxProfiles = _maxProfiles;

        appAddress = _appAddress;
        walletAddress = _walletAddress;

        owner = msg.sender;
        genesis = block.timestamp;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function.");
        _;
    }

    modifier onlyApp() {
        require(msg.sender == appAddress, "Only App can call this function.");
        _;
    }

    modifier stopInEmergency() {
        require(!stopped, "Emergency stop is active, function execution is prevented.");
        _;
    }

    modifier onlyInEmergency() {
        require(stopped, "Not in Emergency, function execution is prevented.");
        _;
    }

    function isClaimable(uint256 roundId, uint256 profileIndex) internal view returns (bool) {
       if (roundToProfiles[roundId].length == 1 && profileIndex == 0) {
            // only one person scenario
            return true;
        } 

        return (((roundToQualify[roundId] >> profileIndex) & 1) == 1);
    }

    function isExcluded(uint256 roundId, uint256 profileIndex) internal view returns (bool) {
        if (roundToProfiles[roundId].length == 1 && profileIndex == 0) {
            // only one person scenario
            return false;
        }

        return (((roundToQualify[roundId] >> (profileIndex + 50)) & 1) == 1);
    }

    function isClaimed(uint256 roundId, uint256 profileIndex) internal view returns (bool) {
        return (((roundToQualify[roundId] >> (profileIndex + 100)) & 1) == 1);
    }

    function setClaimed(uint256 roundId, uint256 profileIndex) internal {
        roundToQualify[roundId] |= (1 << (100 + profileIndex));
    }

    function setExcluded(uint256 roundId, uint256 profileIndex) internal {
        roundToQualify[roundId] |= (1 << (50 + profileIndex));
    }

    function setClaimable(uint256 roundId, uint256 profileIndex) internal {
        roundToQualify[roundId] |= (1 << profileIndex);
    }

    function isOpen(uint256 roundId) internal view returns (bool) {
        uint256 startTime = genesis + roundId * ROUND_GAP_LENGTH;
        return (block.timestamp > startTime && block.timestamp < (startTime + ROUND_OPEN_LENGTH));
    }

    function isSettle(uint256 roundId) internal view returns (bool) {
        return (block.timestamp > (genesis + roundId * ROUND_GAP_LENGTH + ROUND_OPEN_LENGTH + ROUND_FREEZE_LENGTH));
    }

    function payCurrency(address to, uint256 amount) internal {
        require(amount > 0, "Invalid amount");
        currency.safeTransfer(to, amount);
    }

    /**
     * @dev profile claim and transfer fund back
     * @param roundId round id
     * @param profileIndex The index in the profiles array, get by getRoundData
     * @param profileId profile id
     */
    function profileClaim(uint256 roundId, uint256 profileIndex, uint256 profileId) external stopInEmergency {
        // ensure round is settle
        require(isSettle(roundId), "Round is not settle");
        // out-of-bound check
        require(profileIndex < roundToProfiles[roundId].length, "index out of bound");
        require(profileId == roundToProfiles[roundId][profileIndex], "Profile invalid");
        // check address legal
        require(msg.sender == profileToAddress[profileId], "Address not match profile");
        // Check the profile has qualify to claim
        require(isClaimable(roundId, profileIndex), "Profile not qualify to claimed");
        // Check the profile is not exclude
        require(!isExcluded(roundId, profileIndex), "Profile is excluded");
        // Check the profile has not claimed
        require(!isClaimed(roundId, profileIndex), "Profile already claimed");

        // calculate reward && pay

        uint256 profileNum = roundToProfiles[roundId].length;
        uint256 qualifyNum = 0;
        uint256 shares = 0;
        for (uint256 i = 0; i < profileNum; i++) {
            if (isClaimable(roundId, i) && !isExcluded(roundId, i)) {
                qualifyNum += 1;
                shares += inviteBonus[roundId][roundToProfiles[roundId][i]];
            }
        }

        // adition fee to divide
        uint256 reward = stakeValue * (profileNum - qualifyNum);
        uint256 platformReward = reward * rewardFee / 1000;
        uint256 inviteReward = 0;
        if (shares > 0) {
            // someone invited people in, create the inviteReward pool
            inviteReward = reward * inviteFee / 1000;
        }
        // claim value contains staked amount and not-finished-profile's staked amount divided equally excludes inviteBonus portation
        uint256 claimValue = stakeValue + ((reward - platformReward - inviteReward) / qualifyNum);

        if (shares > 0 && inviteBonus[roundId][profileId] > 0) {
            // this profile invited people in, add invite reward
            claimValue = claimValue + inviteReward * inviteBonus[roundId][profileId] / shares;
        }

        // Transfer the fund to profile
        payCurrency(profileToAddress[profileId], claimValue);
        
        // Set the flag indicating that the profile has already claimed
        setClaimed(roundId, profileIndex);

        emit ProfileClaim(roundId, profileId, claimValue);
    }

    /**
     * @dev Each participant stake the fund to the round.
     * @param roundId the round id.
     * @param profileId The ID of len profile.
     * @param profileAddress The address of the profile that staking.
     * @param refId The id that invite this profile
     */
    function profileStake(uint256 roundId, uint256 profileId, address profileAddress, uint256 refId) external stopInEmergency {
        // Check if the msg.sender is the profile owner
        require(msg.sender == profileAddress, "Sender is not the profile owner");
        // Check if the profile address is valid
        require(profileAddress != address(0), "Invalid profile address");
        // Check round is in open stage
        require(isOpen(roundId), "Round is not in open stage");
        // Check profile count
        require(roundToProfiles[roundId].length < maxProfiles, "Maximum profile limit reached");
        // check not staked before
        // total profiles is small, so this loop is ok
        bool alreadyIn = false;
        for (uint32 i = 0; i < roundToProfiles[roundId].length; i += 1) {
            if (roundToProfiles[roundId][i] ==  profileId) {
                alreadyIn = true;
                break;
            }
        }
        require(!alreadyIn, "profile already paticipant");

        // bind address to profile
        profileToAddress[profileId] = profileAddress;

        // free of fee ?
        if (roundToProfiles[roundId].length < firstNFree) {
            // Transfer funds to stake contract
            currency.safeTransferFrom(
                profileAddress,
                address(this),
                stakeValue
            );
            emit ProfileStake(roundId, profileAddress, stakeValue, 0, refId);
        } else {
            // Calculate fee
            uint256 stakeFee = (stakeValue / 1000) * gasFee;

            // Transfer funds to stake contract
            currency.safeTransferFrom(
                profileAddress,
                address(this),
                stakeValue + stakeFee
            );

            // transfer fees
            if (stakeFee > 0) {
                payCurrency(walletAddress, stakeFee);
            }
            emit ProfileStake(roundId, profileAddress, stakeValue, stakeFee, refId);
        }
        
        // add profile
        roundToProfiles[roundId].push(profileId);

        // add round
        profileToRounds[profileId].push(roundId);

        // set invite bonus
        inviteBonus[roundId][refId] += 1;
    }

    /**
     * @dev qualify profile
     */
    function profileQualify(uint256 roundId, uint256 qualify) external stopInEmergency onlyApp {
        require(!isOpen(roundId), "Round is open");
        // ensure round is not settle
        require(!isSettle(roundId), "Round is settle");
        require(qualify > 0, "qualify should not be zero");
        require(roundToProfiles[roundId].length > 0, "profiles is empty");
        // set last #profiles bits
        roundToQualify[roundId] |= (((1 << roundToProfiles[roundId].length) - 1) & qualify);
        emit ProfileQualify(roundId, qualify);
    }

    /**
     * @dev exclude profiles which is illegal
     * @param roundId current round id
     * @param illegals Bit array to indicate profile qualification of claim
     */
    function profileExclude(uint256 roundId, uint256 illegals) external stopInEmergency onlyApp {
        // round not settle
        require(!isSettle(roundId), "Round is settle");
        require(illegals > 0, "qualify should not be zero");
        require(roundToProfiles[roundId].length > 0, "profiles is empty");

        roundToQualify[roundId] |= ((((1 << roundToProfiles[roundId].length) - 1) & illegals) << 50);
        emit ProfileExclude(roundId, illegals);
    }

    function getCurrentRound() public view returns (uint256 roundId, uint256 startTime) {
        uint256 crrentRoundId = (block.timestamp - genesis) / ROUND_GAP_LENGTH;
        return (crrentRoundId, genesis + crrentRoundId * ROUND_GAP_LENGTH);
    }

    function getRoundData(uint256 roundId) public view returns (uint256 qualify, uint256[] memory profiles) {
        return (roundToQualify[roundId], roundToProfiles[roundId]);
    }

    function getProfileRounds(uint256 profileId) public view returns (uint256[] memory roundIds) {
        return profileToRounds[profileId];
    }

    function  getProfileInvites(uint256 roundId, uint256 profileId) public view returns (uint256 invites) {
        return inviteBonus[roundId][profileId];
    }

    function setApp(address _appAddress) public onlyOwner {
        appAddress = _appAddress;
        emit AppSet(_appAddress, msg.sender);
    }

    function getApp() public view returns (address) {
        return appAddress;
    }

    function setGasFee(uint256 fee) public onlyOwner {
        require(fee < 1000, "Fee invalid");
        gasFee = fee;
        emit SetGasFee(fee);
    }

    function getGasFee() public view returns (uint256) {
        return gasFee;
    }

    function setRewardFee(uint256 fee) public onlyOwner {
        require(fee < 1000, "Fee invalid");
        rewardFee = fee;
        emit SetRewardFee(fee);
    }

    function getRewardFee() public view returns (uint256) {
        return rewardFee;
    }

    function setStakeValue(uint256 _stakeValue) public onlyOwner {
        stakeValue = _stakeValue;
        emit SetStakeValue(stakeValue);
    }

    function getStakeValue() public view returns (uint256) {
        return stakeValue;
    }

    function setMaxProfiles(uint256 profiles) public onlyOwner {
        require(profiles <= MAXIMAL_PROFILES && profiles >= firstNFree, "max profiles invalid");
        maxProfiles = profiles;
        emit SetMaxProfiles(profiles);
    }

    function getMaxProfiles() public view returns (uint256) {
        return maxProfiles;
    }

    function setFirstNFree(uint256 n) public onlyOwner {
        require(n <= maxProfiles, "invalid input");
        firstNFree = n;
        emit SetFirstNFree(n);
    }

    function getFirstNFree() public view returns (uint256) {
        return firstNFree;
    }

    function setInviteFee(uint256 fee) public onlyOwner {
        require(fee < 1000, "Fee invalid");
        require(fee + rewardFee < 1000, "Fee invalid");
        inviteFee = fee;
        emit SetInviteFee(fee);
    }

    function getInviteFee() public view returns (uint256) {
        return inviteFee;
    }

    function getConfig() public view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        return (stakeValue, gasFee, rewardFee, maxProfiles, genesis, ROUND_OPEN_LENGTH, ROUND_FREEZE_LENGTH, ROUND_GAP_LENGTH, firstNFree, inviteFee);
    }

    function setWallet(address wallet) public onlyOwner {
        walletAddress = wallet;
        emit WalletSet(wallet, msg.sender);
    }

    function getWallet() public view returns (address) {
        return walletAddress;
    }

    function circuitBreaker() public onlyOwner {
        stopped = !stopped;
        emit CircuitBreak(stopped);
    }

    function withdrawRoundFee(uint256 roundId) public onlyOwner {
        // ensure round is settle
        require(isSettle(roundId), "Round is not settle");

        // calculate reward && pay
        uint256 profileNum = roundToProfiles[roundId].length;
        uint256 qualifyNum = 0;
        for (uint256 i = 0; i < profileNum; i++) {
            if (isClaimable(roundId, i) && !isExcluded(roundId, i)) {
                qualifyNum += 1;
            }
        }

        uint256 reward = stakeValue * (profileNum - qualifyNum);
        uint256 fee = (reward / 1000) * rewardFee;

        // Transfer the fund to profile
        if (fee > 0) {
            payCurrency(walletAddress, fee);
        }
        
        emit WithdrawRoundFee(roundId, fee);
    }

    function withdraw() public onlyInEmergency onlyOwner {
        uint256 balance = currency.balanceOf(address(this));
        // Check that there is enough funds to withdraw
        require(balance > 0, "The fund is empty");

        payCurrency(msg.sender, balance);
        emit Withdraw(balance);
    }

    /** @notice To be able to pay and fallback
     */
    receive() external payable {}

    fallback() external payable {}
}