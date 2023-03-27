import brownie
from brownie import *
from brownie_tokens import ERC20
from datetime import datetime, timedelta
import time
import math

def stake(stake2follow, accounts):
  config = stake2follow.getConfig()
  stakeValue = config[0]
  stakeFee = config[1]

  roundId, roundStartTime = stake2follow.getCurrentRound()

  # 3 paticipants
  stake2follow.profileStake(roundId, 1, accounts[1], {'from': accounts[1]})
  stake2follow.profileStake(roundId, 2, accounts[2], {'from': accounts[2]})
  stake2follow.profileStake(roundId, 3, accounts[3], {'from': accounts[3]})

  return roundId, config[5], config[6], config[7]

def test_claim_at_open_time_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  roundId, roundOpenDur, roundFreezeDur, roundGap = stake(stake2follow, accounts)

  with brownie.reverts():
    stake2follow.profileClaim(roundId, 0, 1, {'from': accounts[1]})


def test_claim_at_freeze_time_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  roundId, roundOpenDur, roundFreezeDur, roundGap = stake(stake2follow, accounts)

  chain.sleep(roundOpenDur)
  chain.mine(1)
  with brownie.reverts():
    stake2follow.profileClaim(roundId, 0, 1, {'from': accounts[1]})

def test_claim_with_no_qualify_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  roundId, roundOpenDur, roundFreezeDur, roundGap = stake(stake2follow, accounts)

  chain.sleep(roundOpenDur + roundFreezeDur)
  chain.mine(1)
  with brownie.reverts():
    stake2follow.profileClaim(roundId, 0, 1, {'from': accounts[1]})

def test_claim_with_qualify_but_exclude_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  roundId, roundOpenDur, roundFreezeDur, roundGap = stake(stake2follow, accounts)

  chain.sleep(roundOpenDur) 
  chain.mine(1)
  stake2follow.profileQualify(roundId, 1, {'from': accounts[8]})
  stake2follow.profileExclude(roundId, 1, {'from': accounts[8]})
  stake2follow.profileQualify(roundId, 0b010, {'from': accounts[8]})
  stake2follow.profileExclude(roundId, 0b010, {'from': accounts[8]})
  chain.sleep(roundFreezeDur)
  chain.mine(1)
  with brownie.reverts():
    stake2follow.profileClaim(roundId, 0, 1, {'from': accounts[1]})

  with brownie.reverts():
    stake2follow.profileClaim(roundId, 1, 2, {'from': accounts[2]})

def test_claim_with_not_matched_profile_index_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  roundId, roundOpenDur, roundFreezeDur, roundGap = stake(stake2follow, accounts)

  chain.sleep(roundOpenDur)
  chain.mine(1)

  stake2follow.profileQualify(roundId, 1, {'from': accounts[8]})

  chain.sleep(roundFreezeDur)
  chain.mine(1)
  with brownie.reverts():
    stake2follow.profileClaim(roundId, 0, 2, {'from': accounts[1]})

def test_claim_with_not_matched_wallet_address_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  roundId, roundOpenDur, roundFreezeDur, roundGap = stake(stake2follow, accounts)

  chain.sleep(roundOpenDur)
  chain.mine(1)

  stake2follow.profileQualify(roundId, 1, {'from': accounts[8]})
  chain.sleep(roundFreezeDur)
  chain.mine(1)
  with brownie.reverts():
    stake2follow.profileClaim(roundId, 0, 1, {'from': accounts[2]})


def test_claim_balance_should_change_as_expected_if_claim_success(accounts, contracts):
  stake2follow, currency = contracts
  roundId, roundOpenDur, roundFreezeDur, roundGap = stake(stake2follow, accounts)

  chain.sleep(roundOpenDur)
  chain.mine(1)

  stake2follow.profileQualify(roundId, 1, {'from': accounts[8]})
  roundData = stake2follow.getRoundData(roundId, {'from': accounts[8]})
  print('round data: ', roundData)

  chain.sleep(roundFreezeDur)

  config = stake2follow.getConfig()
  stakeValue = config[0]
  stakeFee = config[1]
  rewardFee = config[2]

  balanceBeforeClaim = currency.balanceOf(accounts[1])
  print('balance before claim', balanceBeforeClaim)
  walletbalanceBeforeClaim = currency.balanceOf(stake2follow.address)
  print('wallet balance before: ', walletbalanceBeforeClaim)
  
  rewardPool = 2 * stakeValue
  fee = rewardPool * rewardFee / 100
  avgReward = (rewardPool - fee) / 1
  print('pool: ', rewardPool, 'fee: ', fee, 'avgReward: ', avgReward)
  
  t = stake2follow.profileClaim(roundId, 0, 1, {'from': accounts[1]})
  print(t.info())

  balanceAftereClaim = currency.balanceOf(accounts[1])
  walletbalanceAfterClaim = currency.balanceOf(stake2follow.address)
  print('balance after claim: ', balanceAftereClaim)
  print('wallet balance after claim: ', walletbalanceAfterClaim)
  assert balanceAftereClaim == balanceBeforeClaim + stakeValue + avgReward
  assert walletbalanceAfterClaim == walletbalanceBeforeClaim - stakeValue - avgReward



def test_claim_repeat_claim_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  roundId, roundOpenDur, roundFreezeDur, roundGap = stake(stake2follow, accounts)

  chain.sleep(roundOpenDur)
  chain.mine(1)

  stake2follow.profileQualify(roundId, 1, {'from': accounts[8]})

  chain.sleep(roundFreezeDur)

  stake2follow.profileClaim(roundId, 0, 1, {'from': accounts[1]})
  with brownie.reverts():
    stake2follow.profileClaim(roundId, 0, 1, {'from': accounts[1]})


def test_claim_all_profiles_claimable_balance_should_change_as_expected(accounts, contracts):
  stake2follow, currency = contracts
  roundId, roundOpenDur, roundFreezeDur, roundGap = stake(stake2follow, accounts)

  chain.sleep(roundOpenDur)
  chain.mine(1)

  stake2follow.profileQualify(roundId, 1, {'from': accounts[8]})
  stake2follow.profileQualify(roundId, 2, {'from': accounts[8]})
  stake2follow.profileQualify(roundId, 4, {'from': accounts[8]})

  chain.sleep(roundFreezeDur)

  config = stake2follow.getConfig()
  stakeValue = config[0]
  stakeFee = config[1]
  rewardFee = config[2]

  balanceBeforeClaim1 = currency.balanceOf(accounts[1])
  balanceBeforeClaim2 = currency.balanceOf(accounts[2])
  balanceBeforeClaim3 = currency.balanceOf(accounts[3])
  walletbalanceBeforeClaim = currency.balanceOf(stake2follow.address)
  
  stake2follow.profileClaim(roundId, 0, 1, {'from': accounts[1]})
  stake2follow.profileClaim(roundId, 1, 2, {'from': accounts[2]})
  stake2follow.profileClaim(roundId, 2, 3, {'from': accounts[3]})

  balanceAftereClaim1 = currency.balanceOf(accounts[1])
  balanceAftereClaim2 = currency.balanceOf(accounts[1])
  balanceAftereClaim3 = currency.balanceOf(accounts[1])
  walletbalanceAfterClaim = currency.balanceOf(stake2follow.address)

  assert balanceAftereClaim1 == balanceBeforeClaim1 + stakeValue
  assert balanceAftereClaim2 == balanceBeforeClaim2 + stakeValue
  assert balanceAftereClaim3 == balanceBeforeClaim3 + stakeValue
  assert walletbalanceAfterClaim == walletbalanceBeforeClaim - 3 * stakeValue

def test_claim_no_profiles_claimable_balance_should_change_as_expected(accounts, contracts):
  stake2follow, currency = contracts

  beforeValue = currency.balanceOf(stake2follow.address)
  roundId, roundOpenDur, roundFreezeDur, roundGap = stake(stake2follow, accounts)

  chain.sleep(roundOpenDur)
  chain.mine(1)


  chain.sleep(roundFreezeDur)

  config = stake2follow.getConfig()
  stakeValue = config[0]
  stakeFee = config[1]
  rewardFee = config[2]

  with brownie.reverts():
    stake2follow.profileClaim(roundId, 2, 3, {'from': accounts[3]})

  afterValue = currency.balanceOf(stake2follow.address)

  assert afterValue == beforeValue + 3 * stakeValue 