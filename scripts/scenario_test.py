
from brownie import stake2Follow, accounts
from brownie_tokens import ERC20

def main():

  # create a currency(like wMatic)
  currency =  ERC20()
  # mint to accounts
  for i in range(1, 8):
    currency._mint_for_testing(accounts[i], 1e8)
    print('mint currency for account {}: {}'.format(i, currency.balanceOf(accounts[i])))

  # deploy contract
  fee = 5
  sf = stake2Follow.deploy(fee, currency.address, {'from': accounts[0]})

  # ATTENSION: we should first get accounts approve to stake
  for i in range(1, 8):
    currency.approve(sf.address, 10000, {'from': accounts[i]})

  # set fee
  fee = 10
  sf.setFee(fee, {'from': accounts[0]})
  print('fee changed to {}'.format(sf.getFee()))

  # set hub address
  sf.setHub(accounts[8], {'from': accounts[0]})
  print('hub address: {} vs {}'.format(sf.getHub(), accounts[8]))

  # set multi-sig
  sf.setMultisig(accounts[9], {'from': accounts[0]})
  print('multisig: {} vs {}'.format(sf.getMultisig(), accounts[9]))

  # round start
  roundId = '#round_1'

  # profiles stake
  fund = 1000
  fee = (fund / 100) * 10
  print('fee: ', fee)
  for i in range(1, 8):
    sf.profileStake(fund + fee, roundId, accounts[i], {'from': accounts[i]})
    print('account {} staked'.format(i))

  # withdraw is allowed before freeze
  sf.profileWithdraw(roundId, accounts[7], {'from': accounts[7]})

  # freeze
  sf.roundFreeze(roundId, {'from': accounts[8]})
  print('current total fund: {} vs {}'.format(sf.getRoundFund(roundId), currency.balanceOf(sf.address)))
  print('fee collected: {}'.format(currency.balanceOf(accounts[9])))

  # open claim
  sf.roundClaim(roundId, {'from': accounts[8]})

  sf.profileClaim(roundId, accounts[1], 1000, {'from': accounts[8]})
  sf.profileClaim(roundId, accounts[2], 2000, {'from': accounts[8]})
  sf.profileClaim(roundId, accounts[3], 1000, {'from': accounts[8]})
  print('current total fund: {}'.format(sf.getRoundFund(roundId)))


  ####### In emergency ###########
  sf.circuitBreaker({'from': accounts[0]})

  # withdraw all the remaining funds in this round
  #sf.withdrawRound(roundId, {'from': accounts[8]})
  #print('hub withdrawed: {}'.format(currency.balanceOf(accounts[8])))

  # withdraw: all the fund in this contract transferd to contract deployer
  sf.withdraw()
  print('owner withdrawed: {}'.format(currency.balanceOf(accounts[0])))







