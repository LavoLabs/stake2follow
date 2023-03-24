import brownie

def test_set_get_gas_fee(accounts, contracts):
  stake2follow, currency = contracts
  stake2follow.setGasFee(5, {'from': accounts[0]})
  assert stake2follow.getGasFee() == 5

  with brownie.reverts():
    stake2follow.setGasFee(5, {'from': accounts[8]})

  with brownie.reverts():
    stake2follow.setGasFee(5, {'from': accounts[9]})

  with brownie.reverts():
    stake2follow.setGasFee(101, {'from': accounts[0]})


def test_set_get_reward_fee(accounts, contracts):
  stake2follow, currency = contracts
  stake2follow.setRewardFee(5, {'from': accounts[0]})
  assert stake2follow.getRewardFee() == 5

  with brownie.reverts():
    stake2follow.setRewardFee(5, {'from': accounts[8]})

  with brownie.reverts():
    stake2follow.setRewardFee(5, {'from': accounts[9]})

  with brownie.reverts():
    stake2follow.setRewardFee(101, {'from': accounts[0]})

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

  stake2follow.setMaxProfiles(5, {'from': accounts[0]})
  assert stake2follow.getMaxProfiles() == 5

def test_circuit_breaker(accounts, contracts):
  stake2follow, currency = contracts
  with brownie.reverts():
    stake2follow.circuitBreaker({'from': accounts[8]})

  stake2follow.circuitBreaker({'from': accounts[0]})

  roundId, roundStartTime = stake2follow.getCurrentRound()
  with brownie.reverts():
    stake2follow.profileStake(roundId, 1, accounts[1], {'from': accounts[1]})


def test_withdraw(accounts, contracts):
  stake2follow, currency = contracts

  beforeBalance = currency.balanceOf(accounts[0])

  roundId, roundStartTime = stake2follow.getCurrentRound()
  stake2follow.profileStake(roundId, 1, accounts[1], {'from': accounts[1]})

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