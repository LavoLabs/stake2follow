// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "OpenZeppelin/openzeppelin-contracts@4.5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@4.5.0/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@4.5.0/contracts/token/ERC721/IERC721.sol";

import "../interfaces/ILensHub.sol";

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

    ILensHub public lensHub;

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

    uint256 public constant MAXIMAL_PROFILES = 50;

    // uint256 public constant ROUND_OPEN_LENGTH = 3 hours;
    // uint256 public constant ROUND_FREEZE_LENGTH = 50 minutes;
    // uint256 public constant ROUND_GAP_LENGTH = 4 hours;

    uint256 public constant ROUND_OPEN_LENGTH = 15 minutes;
    uint256 public constant ROUND_FREEZE_LENGTH = 5 minutes;
    uint256 public constant ROUND_GAP_LENGTH = 20 minutes;

    // Events
    event ProfileStake(uint256 roundId, address profileAddress, uint256 stake, uint256 fees);
    event ProfileQualify(uint256 roundId, uint256 profileId);
    event ProfileExclude(uint256 roundId, uint256 profileId);
    event ProfileClaim(uint256 roundId, uint256 profileId, uint256 fund);
    event AppSet(address app, address sender);
    event WalletSet(address wallet, address sender);
    event CircuitBreak(bool stop);
    event SetGasFee(uint256 fee);
    event SetRewardFee(uint256 fee);
    event SetMaxProfiles(uint256 profiles);
    event SetStakeValue(uint256 value);
    event SetFirstNFree(uint256 n);
    event WithdrawRoundFee(uint256 roundId, uint256 fee);
    event Withdraw(uint256 balance);

    constructor(uint256 _stakeValue, uint256 _gasFee, uint256 _rewardFee, uint8 _maxProfiles, address _currency, address _appAddress, address _walletAddress, address _lenHubAddress) {
        currency = IERC20(_currency);
        lensHub = ILensHub(_lenHubAddress);

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
        return (((roundToQualify[roundId] >> profileIndex) & 1) == 1);
    }

    function isExcluded(uint256 roundId, uint256 profileIndex) internal view returns (bool) {
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

        bool followAll = true;
        uint256 profileNum = roundToProfiles[roundId].length;
        uint256 qualifyNum = 0;
        for (uint256 i = 0; i < profileNum; i++) {
            if (isClaimable(roundId, i) && !isExcluded(roundId, i)) {
                qualifyNum += 1;
            }
            // check still follows
            if (profileId != roundToProfiles[roundId][i] && !isExcluded(roundId, i)) {
                // query lenshub
                address nftAddress = lensHub.getFollowNFT(roundToProfiles[roundId][i]);
                IERC721 followNFT = IERC721(nftAddress);

                // check follow or not
                if (followNFT.balanceOf(profileToAddress[profileId]) == 0) {
                    followAll = false;
                    break;
                }
            }
        }
        require(followAll, "follow check fail");

        // adition fee to divide
        uint256 reward = stakeValue * (profileNum - qualifyNum);
        uint256 fee = (reward / 1000) * rewardFee;
        uint256 claimValue = stakeValue + ((reward - fee) / qualifyNum);

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
     */
    function profileStake(uint256 roundId, uint256 profileId, address profileAddress) external stopInEmergency {
        // Check if the msg.sender is the profile owner
        require(msg.sender == profileAddress, "Sender is not the profile owner");
        // Check if the profile address is valid
        require(profileAddress != address(0), "Invalid profile address");
        // Check round is in open stage
        require(isOpen(roundId), "Round is not in open stage");
        // Check profile count
        require(roundToProfiles[roundId].length < maxProfiles, "Maximum profile limit reached");
        // TODO: check not staked before
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
            emit ProfileStake(roundId, profileAddress, stakeValue, 0);
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
            emit ProfileStake(roundId, profileAddress, stakeValue, stakeFee);
        }
        
        // add profile
        roundToProfiles[roundId].push(profileId);

        // add round
        profileToRounds[profileId].push(roundId);
    }

    /**
     * @dev qualify profile
     */
    function profileQualify(uint256 roundId, uint256 profileId, address profileAddress) external stopInEmergency {
        require(!isOpen(roundId), "Round is open");
        require(!isSettle(roundId), "Round is settle");
        require(lensHub.getFollowModule(profileId) == address(0), 'Follow module set!');

        bool alreadyIn = false;
        uint256 profileIdx = 0;
        for (uint32 i = 0; i < roundToProfiles[roundId].length; i += 1) {
            if (roundToProfiles[roundId][i] ==  profileId) {
                profileIdx = i;
                alreadyIn = true;
                break;
            }
        }
        require(alreadyIn, "profile not paticipant");

        bool followAll = true;
        for (uint32 i = 0; i < roundToProfiles[roundId].length; i += 1) {
            if (roundToProfiles[roundId][i] !=  profileId) {
                if (isExcluded(roundId, roundToProfiles[roundId][i])) {
                    continue;
                }

                // query lenshub
                address nftAddress = lensHub.getFollowNFT(roundToProfiles[roundId][i]);
                IERC721 followNFT = IERC721(nftAddress);

                // check follow module
                if (lensHub.getFollowModule(roundToProfiles[roundId][i]) != address(0)) {
                    setExcluded(roundId, i);
                    continue;
                }

                // check follow or not
                if (followNFT.balanceOf(profileAddress) == 0) {
                    followAll = false;
                    break;
                }
            }
        }
        require(followAll, "follow mission not completed!");

        // set bit
        setClaimable(roundId, profileIdx);
        emit ProfileQualify(roundId, profileId);
    }

    /**
     * @dev exclude profiles which is illegal
     * @param roundId current round id
     * @param profileId id of profile to exclude
     */
    function profileExclude(uint256 roundId, uint256 profileId) external stopInEmergency onlyApp {
        require(!isSettle(roundId), "Round is settle");
        require(roundToProfiles[roundId].length > 0, "profiles is empty");

        bool alreadyIn = false;
        uint256 profileIdx = 0;
        for (uint32 i = 0; i < roundToProfiles[roundId].length; i += 1) {
            if (roundToProfiles[roundId][i] ==  profileId) {
                profileIdx = i;
                alreadyIn = true;
                break;
            }
        }
        require(alreadyIn, "profile not paticipant");

        require(lensHub.getFollowModule(profileId) == address(0), 'Follow module is not set!');

        setExcluded(roundId, profileIdx);
        emit ProfileExclude(roundId, profileId);
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

    function getConfig() public view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        return (stakeValue, gasFee, rewardFee, maxProfiles, genesis, ROUND_OPEN_LENGTH, ROUND_FREEZE_LENGTH, ROUND_GAP_LENGTH, firstNFree);
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