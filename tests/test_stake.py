import brownie
from datetime import datetime, timedelta

def test_stake(accounts, stake2follow):
  freezeTime = datetime.now() + timedelta(minutes=30)

  stake2follow.openRound(freezeTime.timestamp(), {'from': accounts[8]})
  stake2follow.profileStake(0x01, accounts[1], {'from': accounts[1]})