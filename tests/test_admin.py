import brownie
from brownie import *

def test_set_get_gas_fee(accounts, contracts):
  stake2follow, currency = contracts
  stake2follow.setGasFee(500, {'from': accounts[0]})
  assert stake2follow.getGasFee() == 500

  with brownie.reverts():
    stake2follow.setGasFee(5, {'from': accounts[8]})

  with brownie.reverts():
    stake2follow.setGasFee(5, {'from': accounts[9]})

  with brownie.reverts():
    stake2follow.setGasFee(1001, {'from': accounts[0]})


def test_set_get_reward_fee(accounts, contracts):
  stake2follow, currency = contracts
  stake2follow.setRewardFee(500, {'from': accounts[0]})
  assert stake2follow.getRewardFee() == 500

  with brownie.reverts():
    stake2follow.setRewardFee(5, {'from': accounts[8]})

  with brownie.reverts():
    stake2follow.setRewardFee(5, {'from': accounts[9]})

  with brownie.reverts():
    stake2follow.setRewardFee(1001, {'from': accounts[0]})

def test_set_get_app(accounts, contracts):
  stake2follow, currency = contracts
  
  with brownie.reverts():
    stake2follow.setApp(accounts[5], {'from': accounts[8]})

  with brownie.reverts():
    stake2follow.setApp(accounts[5], {'from': accounts[9]})

  stake2follow.setApp(accounts[5], {'from': accounts[0]})
  assert stake2follow.getApp() == accounts[5]

def test_set_get_wallet(accounts, contracts):
  stake2follow, currency = contracts

  with brownie.reverts():
    stake2follow.setWallet(accounts[5], {'from': accounts[8]})

  with brownie.reverts():
    stake2follow.setWallet(accounts[5], {'from': accounts[9]})

  stake2follow.setWallet(accounts[5], {'from': accounts[0]})
  assert stake2follow.getWallet() == accounts[5]


def test_set_get_stake_value(accounts, contracts):
  stake2follow, currency = contracts

  with brownie.reverts():
    stake2follow.setStakeValue(5, {'from': accounts[8]})

  with brownie.reverts():
    stake2follow.setStakeValue(5, {'from': accounts[9]})

  stake2follow.setStakeValue(5, {'from': accounts[0]})
  assert stake2follow.getStakeValue() == 5


def test_set_get_max_profiles(accounts, contracts):
  stake2follow, currency = contracts
  with brownie.reverts():
    stake2follow.setMaxProfiles(5, {'from': accounts[8]})

  with brownie.reverts():
    stake2follow.setMaxProfiles(59, {'from': accounts[0]})

  with brownie.reverts():
    # no less than @firstNFree
    stake2follow.setFirstNFree(3)
    stake2follow.setMaxProfiles(stake2follow.getFirstNFree() - 1, {'from': accounts[0]})

  stake2follow.setMaxProfiles(5, {'from': accounts[0]})
  assert stake2follow.getMaxProfiles() == 5

def test_set_get_first_n_free(accounts, contracts):
  stake2follow, currency = contracts
  with brownie.reverts():
    stake2follow.setFirstNFree(stake2follow.getMaxProfiles() + 1, {'from': accounts[8]})

  stake2follow.setFirstNFree(5, {'from': accounts[0]})
  assert stake2follow.getFirstNFree() == 5

def test_circuit_breaker(accounts, contracts):
  stake2follow, currency = contracts
  with brownie.reverts():
    stake2follow.circuitBreaker({'from': accounts[8]})

  stake2follow.circuitBreaker({'from': accounts[0]})

  roundId, roundStartTime = stake2follow.getCurrentRound()
  with brownie.reverts():
    stake2follow.profileStake(roundId, 1, accounts[1], 0, {'from': accounts[1]})


def test_withdraw_round(accounts, contracts):
  stake2follow, currency = contracts
  config = stake2follow.getConfig()
  stakeValue = config[0]
  stakeFee = config[1]
  rewardFee = config[2]
  roundOpenDur = config[5]
  roundFreezeDur = config[6]

  stake2follow.setFirstNFree(0)

  beforeBalance = currency.balanceOf(accounts[9])
  roundId, roundStartTime = stake2follow.getCurrentRound()
  chain.mine(1)
  stake2follow.profileStake(roundId, 1, accounts[1], 0, {'from': accounts[1]})
  stake2follow.profileStake(roundId, 2, accounts[2], 0, {'from': accounts[2]})
  stake2follow.profileStake(roundId, 3, accounts[3], 0, {'from': accounts[3]})
  stake2follow.profileStake(roundId, 4, accounts[4], 0, {'from': accounts[4]})
  stake2follow.profileStake(roundId, 5, accounts[5], 0, {'from': accounts[5]})
  middleBalance = currency.balanceOf(accounts[9])

  gasFee = 5 * stakeValue / 1000 * stakeFee
  assert middleBalance == beforeBalance + gasFee

  chain.sleep(roundOpenDur)
  chain.mine(1)

  stake2follow.profileQualify(roundId, 1, {'from': accounts[8]})
  stake2follow.profileQualify(roundId, 2, {'from': accounts[8]})

  chain.sleep(roundFreezeDur)
  chain.mine(1)

  stake2follow.withdrawRoundFee(roundId)
  afterBalance = currency.balanceOf(accounts[9])
  rewardFee = 3 * stakeValue / 1000 * rewardFee
  
  assert afterBalance == beforeBalance + gasFee + rewardFee





def test_withdraw(accounts, contracts):
  stake2follow, currency = contracts

  beforeBalance = currency.balanceOf(accounts[0])

  roundId, roundStartTime = stake2follow.getCurrentRound()
  stake2follow.profileStake(roundId, 1, accounts[1], 0, {'from': accounts[1]})

  contractBalance = currency.balanceOf(stake2follow.address)
  print('contract balance: ', contractBalance)
  with brownie.reverts():
    stake2follow.withdraw({'from': accounts[8]})

  with brownie.reverts():
    stake2follow.withdraw({'from': accounts[0]})

  stake2follow.circuitBreaker({'from': accounts[0]})
  with brownie.reverts():
    stake2follow.withdraw({'from': accounts[8]})
  stake2follow.withdraw({'from': accounts[0]})

  afterBalance = currency.balanceOf(accounts[0])
  assert afterBalance == beforeBalance + contractBalance