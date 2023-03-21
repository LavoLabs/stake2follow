
from brownie import stake2Follow, accounts
from brownie import Contract
import json


def deploy():

  usdcAddress = '0xE097d6B3100777DC31B34dC2c58fB524C2e76921'
  f = open('./scripts/usdc-imp-abi.json')
  binary = json.load(f)
  abi = json.loads(binary['result'])
  usdc = Contract.from_abi('USDC', usdcAddress, abi)

  # deploy contract
  stakeValue = 2e6
  gasFee = 5
  rewardFee = 10
  maxProfiles = 20
  sf = stake2Follow.deploy(
    stakeValue,
    gasFee,
    rewardFee,
    maxProfiles,
    usdc.address, {'from': accounts[0]}
  )
  return sf, usdc