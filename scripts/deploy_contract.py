
from brownie import stake2Follow, accounts, Token


def main():
    wmatic = Token.deploy('Wrapped Matic', 'wMATIC', 18, 10000 * 1e18, {'from': accounts[0]})
    stakeValue = 5*1e18
    gasFee = 5
    rewardFee = 10
    maxProfiles = 20
    sf = stake2Follow.deploy(stakeValue, gasFee, rewardFee, maxProfiles, wmatic.address, {'from': accounts[0]})

    sf.setHub(accounts[8], {'from': accounts[0]})
    sf.setMultisig(accounts[9], {'from': accounts[0]})
    for i in range(1, 8):
        wmatic.approve(sf.address, 5 * (1 + 0.05) * 1e18, {'from': accounts[i]})