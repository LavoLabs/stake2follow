
from brownie import stake2Follow, accounts, Token

def createMatic():
    wmatic = Token.deploy('Wrapped Matic', 'wMATIC', 18, 1000000 * 1e18, {'from': accounts[0]})
    print("create token address: ", wmatic.address)
    return wmatic

def createContract(wmatic):
    stakeValue = 5*1e18
    gasFee = 5
    rewardFee = 10
    maxProfiles = 5
    sf = stake2Follow.deploy(stakeValue, gasFee, rewardFee, maxProfiles, wmatic.address, {'from': accounts[0]})
    print("create contract, address: ", sf.address)
    return sf

def init():
    matic = createMatic()
    sf = createContract(matic)

    hubKey = '0x7Ed63873E7A526090AdE08e9F4A5b1c5e2D75835'
    sf.setHub(hubKey, {'from': accounts[0]})

    sf.setMultisig(accounts[9], {'from': accounts[0]})
    for i in range(1, 9):
        matic.approve(sf.address, 50 * (1 + 0.05) * 1e18, {'from': accounts[i]})
        matic.transfer(accounts[i], 100*1e18, {'from': accounts[0]})

    # transfer some ether to hub
    accounts[9].transfer(hubKey, '10 ether')

    return [sf, matic]