import brownie

def test_stake(accounts, stake2follow):
  stake2follow.profileStake(110, "#round1", accounts[1], {'from': accounts[1]})