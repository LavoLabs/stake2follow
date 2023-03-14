
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

  # qualifies = 2
  # bits = 0
  # bits |= (1 << 3)
  # bits |= (1 << 6)
  # bits = (bits << 8) | qualifies

  # print(bits)
  # print("{0:b}".format(bits))
  # tx = sf.test(bits)
  # print(tx.events)
  # return

  # ATTENSION: we should first get accounts approve to stake
  for i in range(1, 8):
    currency.approve(sf.address, 10000, {'from': accounts[i]})

  # set fee
  gasFee = 10
  sf.setGasFee(gasFee, {'from': accounts[0]})
  print('fee changed to {}'.format(sf.getGasFee()))

  # set hub address
  sf.setHub(accounts[8], {'from': accounts[0]})
  print('hub address: {} vs {}'.format(sf.getHub(), accounts[8]))

  # set multi-sig
  sf.setMultisig(accounts[9], {'from': accounts[0]})
  print('multisig: {} vs {}'.format(sf.getMultisig(), accounts[9]))

  # round start
  roundId = '#round_1'

  # profiles stake
  for i in range(1, 8):
    tx = sf.profileStake(roundId, accounts[i], {'from': accounts[i]})
    print('account {} staked'.format(i))
    print(tx.events)


  # freeze
  tx = sf.roundFreeze(roundId, {'from': accounts[8]})
  print('current total fund: {} vs {}'.format(sf.getRoundFund(roundId), currency.balanceOf(sf.address)))
  print('fee collected: {}'.format(currency.balanceOf(accounts[9])))
  print('round data:')
  print(tx.return_value)

  # open claim
  qualifies = 3
  bits = 0
  bits |= (1 << 0)
  bits |= (1 << 1)
  bits |= (1 << 3)
  bits = (bits << 8) | qualifies
  tx = sf.roundClaim(roundId, bits, {'from': accounts[8]})
  print(tx.events)

  tx = sf.profileClaim(roundId, accounts[1], {'from': accounts[8]})
  print(tx.events)
  tx = sf.profileClaim(roundId, accounts[2], {'from': accounts[8]})
  print(tx.events)
  # tx = sf.profileClaim(roundId, accounts[4], {'from': accounts[8]})
  # print(tx.events)
  print('current total fund: {}'.format(sf.getRoundFund(roundId)))
  tx = sf.getRoundData.call(roundId)
  print('round data: ')
  print(tx)

  ####### In emergency ###########
  sf.circuitBreaker({'from': accounts[0]})

  # withdraw all the remaining funds in this round
  #sf.withdrawRound(roundId, {'from': accounts[8]})
  #print('hub withdrawed: {}'.format(currency.balanceOf(accounts[8])))

  # withdraw: all the fund in this contract transferd to contract deployer
  sf.withdraw()
  print('owner withdrawed: {}'.format(currency.balanceOf(accounts[0])))







