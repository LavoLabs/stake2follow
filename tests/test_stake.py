import brownie
from brownie import *
from brownie_tokens import ERC20
import time
import math

def test_stake_at_round_open_success(accounts, contracts):
  stake2follow, currency = contracts
  config = stake2follow.getConfig()
  stakeValue = config[0]
  stakeFee = config[1]

  roundId, roundStartTime = stake2follow.getCurrentRound()
  balanceContractBefore = currency.balanceOf(stake2follow.address)
  balanceBefore = currency.balanceOf(accounts[1])
  walletBalanceBefore = currency.balanceOf(accounts[9])
  print('balance: ', balanceBefore, walletBalanceBefore)
  stake2follow.profileStake(roundId, 1, accounts[1], {'from': accounts[1]})
  # first one is free
  fee = 0 #math.floor(stakeValue * stakeFee / 100)
  cost = stakeValue + fee
  balanceAfter = currency.balanceOf(accounts[1])
  walletBalanceAfter = currency.balanceOf(accounts[9])
  balanceContractAfter = currency.balanceOf(stake2follow.address)
  assert balanceBefore == balanceAfter + cost
  assert walletBalanceAfter == walletBalanceBefore + fee
  assert balanceContractAfter == balanceContractBefore + stakeValue

def test_stake_not_owner_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  with brownie.reverts():
    roundId, roundStartTime = stake2follow.getCurrentRound()
    stake2follow.profileStake(roundId, 1, accounts[1], {'from': accounts[2]})

def test_stake_future_roundid_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  with brownie.reverts():
    stake2follow.profileStake(1, 1, accounts[1], {'from': accounts[1]})
    stake2follow.profileStake(100, 1, accounts[1], {'from': accounts[1]})

def test_stake_not_at_open_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  config = stake2follow.getConfig()
  roundOpenDur = config[5]
  roundFreezeDur = config[6]
  roundGap = config[7]
  roundId, roundStartTime = stake2follow.getCurrentRound()

  # freeze stage
  chain.sleep(roundOpenDur)
  chain.mine(1)
  with brownie.reverts():
    stake2follow.profileStake(roundId, 1, accounts[1], {'from': accounts[1]})

  # settle stage
  chain.sleep(roundFreezeDur)
  chain.mine(1)
  with brownie.reverts():
    stake2follow.profileStake(roundId, 1, accounts[1], {'from': accounts[1]})

def test_stake_exceed_max_profiles_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  config = stake2follow.getConfig()
  stakeValue = config[0]
  stakeFee = config[1]
  maxProfiles = config[3]
  roundId, roundStartTime = stake2follow.getCurrentRound()

  firstNFree = stake2follow.getFirstNFree()
  for i in range(maxProfiles):
    print('user : ', i, accounts[i + 1])
    balanceBefore = currency.balanceOf(accounts[i + 1])
    stake2follow.profileStake(roundId, i, accounts[i + 1], {'from': accounts[i + 1]})
    fee = math.floor(stakeValue * stakeFee / 100)
    if i < firstNFree:
      fee = 0
    cost = stakeValue + fee
    balanceAfter = currency.balanceOf(accounts[i + 1])
    assert balanceBefore == balanceAfter + cost
    time.sleep(1)

  with brownie.reverts():
    stake2follow.profileStake(roundId, maxProfiles+1, accounts[maxProfiles + 1], {'from': accounts[maxProfiles + 1]})

def test_stake_twice_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  config = stake2follow.getConfig()
  roundId, roundStartTime = stake2follow.getCurrentRound()
  stake2follow.profileStake(roundId, 1, accounts[1], {'from': accounts[1]})
  with brownie.reverts():
    stake2follow.profileStake(roundId, 1, accounts[1], {'from': accounts[1]})
