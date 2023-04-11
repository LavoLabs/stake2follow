import brownie
from brownie import *
from datetime import datetime, timedelta
import time
import math

def test_get_config(accounts, contracts):
  stake2follow, currency = contracts

  stake2follow.setStakeValue(100)
  stake2follow.setGasFee(9)
  stake2follow.setRewardFee(8)
  stake2follow.setMaxProfiles(10)

  config = stake2follow.getConfig()

  assert config[0] == 100
  assert config[1] == 9
  assert config[2] == 8
  assert config[3] == 10

def current_round(config):
  return math.floor((datetime.now().timestamp() - config[4]) / config[7])


def test_get_curent_round(accounts, contracts):
  stake2follow, currency = contracts

  config = stake2follow.getConfig()
  genesis = config[4]
  roundOpenDur = config[5]
  roundFreezeDur = config[6]
  roundGap = config[7]

  roundId = current_round(config)
  assert roundId == 0

  # fast-forward
  for i in range(10):
    chain.sleep(roundGap)
    chain.mine(1)

    roundId += 1

    roundData = stake2follow.getCurrentRound()
    assert roundId == roundData[0]


def test_get_round_data(accounts, contracts):
  stake2follow, currency = contracts
  config = stake2follow.getConfig()
  genesis = config[4]
  roundOpenDur = config[5]
  roundFreezeDur = config[6]
  roundGap = config[7]

  roundId = current_round(config)
  assert roundId == 0

  # fast-forward
  for i in range(10):
    roundId, roundStartTime = stake2follow.getCurrentRound()
    stake2follow.profileStake(roundId, 1, accounts[1], 0, {'from': accounts[1]})

    chain.sleep(roundOpenDur)
    chain.mine(1)
    stake2follow.profileQualify(roundId, 1, {'from': accounts[8]})

    chain.sleep(roundFreezeDur)
    chain.mine(1)
    qualify, profiles = stake2follow.getRoundData(roundId, {'from': accounts[8]})
    assert qualify == 1
    assert len(profiles) == 1

    chain.sleep(roundGap - roundOpenDur - roundFreezeDur)
    chain.mine(1)


def test_get_profile_rounds(accounts, contracts):
  stake2follow, currency = contracts
  config = stake2follow.getConfig()
  genesis = config[4]
  roundOpenDur = config[5]
  roundFreezeDur = config[6]
  roundGap = config[7]

  roundId = current_round(config)
  assert roundId == 0

  # fast-forward
  for i in range(10):
    chain.sleep(roundGap)
    chain.mine(1)

    roundId, roundStartTime = stake2follow.getCurrentRound()
    stake2follow.profileStake(roundId, 1, accounts[1], 0, {'from': accounts[1]})

  rounds = stake2follow.getProfileRounds(1, {'from': accounts[8]})
  assert len(rounds) == 10