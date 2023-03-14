#!/usr/bin/python3

import pytest
from brownie import stake2Follow
from brownie_tokens import ERC20

@pytest.fixture(scope="function", autouse=True)
def isolate(fn_isolation):
    # perform a chain rewind after completing each test, to ensure proper isolation
    # https://eth-brownie.readthedocs.io/en/v1.10.3/tests-pytest-intro.html#isolation-fixtures
    pass



@pytest.fixture(scope="module")
def stake2follow(stake2Follow, accounts):
  currency =  ERC20()
  for i in range(1, 8):
    currency._mint_for_testing(accounts[i], 1e5)

  # deploy contract
  stakeValue = 1000
  gasFee = 5
  rewardFee = 10
  maxProfiles = 20
  sf = stake2Follow.deploy(
    stakeValue,
    gasFee,
    rewardFee,
    maxProfiles,
    currency.address, {'from': accounts[0]}
  )

  # set hub address
  sf.setHub(accounts[8], {'from': accounts[0]})

  # set multi-sig
  sf.setMultisig(accounts[9], {'from': accounts[0]})

  for i in range(1, 8):
    currency.approve(sf.address, 10000, {'from': accounts[i]})

  return sf
