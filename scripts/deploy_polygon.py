
from brownie import stake2Follow, accounts
from brownie import Contract
import json


def deploy():
  wMaticAddress = '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270'

  # hub and sig
  accounts.load('sf_owner')
  owner = accounts[0]
  appAddress = '0x509445190B91D646C2e6973409894f39Ba5d1c52'
  walletAddress = '0xeDB79a63c3A888D806463D82f7ca29511e5437AD'

  # deploy contract
  stakeValue = 5e18
  gasFee = 4
  rewardFee = 0
  maxProfiles = 20
  sf = stake2Follow.deploy(
    stakeValue,
    gasFee,
    rewardFee,
    maxProfiles,
    wMaticAddress,
    appAddress,
    walletAddress,
    {'from': owner}
  )

  return sf