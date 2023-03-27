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

def test_exclude_at_settle_time_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  roundId, roundOpenDur, roundFreezeDur, roundGap = stake(stake2follow, accounts)

  chain.sleep(roundOpenDur + roundFreezeDur)
  chain.mine(1)
  with brownie.reverts():
    stake2follow.profileExclude(roundId, 1, {'from': accounts[8]})

def test_exclude_at_freeze_time_success(accounts, contracts):
  stake2follow, currency = contracts
  roundId, roundOpenDur, roundFreezeDur, roundGap = stake(stake2follow, accounts)

  chain.sleep(roundOpenDur)
  chain.mine(1)
  stake2follow.profileExclude(roundId, 1, {'from': accounts[8]})

  # check bit is set
  qualify, profiles = stake2follow.getRoundData(roundId,  {'from': accounts[8]})
  assert (qualify >> 50) == 1
  assert len(profiles) == 3

  stake2follow.profileExclude(roundId, 0b100, {'from': accounts[8]})
  qualify, profiles = stake2follow.getRoundData(roundId, {'from': accounts[8]})
  assert (qualify >> 50) == 0b101
  assert len(profiles) == 3

  stake2follow.profileExclude(roundId, 0b111010, {'from': accounts[8]})
  qualify, profiles = stake2follow.getRoundData(roundId,  {'from': accounts[8]})
  assert (qualify >> 50) == 0b111
  assert len(profiles) == 3


def test_exclude_with_zero_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  roundId, roundOpenDur, roundFreezeDur, roundGap = stake(stake2follow, accounts)

  chain.sleep(roundOpenDur)
  chain.mine(1)

  with brownie.reverts():
    stake2follow.profileExclude(roundId, 0, {'from': accounts[8]})

def test_exclude_with_no_paticipants_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  config = stake2follow.getConfig()
  stakeValue = config[0]
  stakeFee = config[1]

  roundId, roundStartTime = stake2follow.getCurrentRound()
  with brownie.reverts():
    stake2follow.profileExclude(roundId, 1, {'from': accounts[8]})

def test_exclude_using_not_app_address_should_fail(accounts, contracts):
  stake2follow, currency = contracts
  roundId, roundOpenDur, roundFreezeDur, roundGap = stake(stake2follow, accounts)

  chain.sleep(roundOpenDur)
  chain.mine(1)
  with brownie.reverts():
    stake2follow.profileExclude(roundId, 1, {'from': accounts[0]})
    stake2follow.profileExclude(roundId, 1, {'from': accounts[1]})
    stake2follow.profileExclude(roundId, 1, {'from': accounts[9]})