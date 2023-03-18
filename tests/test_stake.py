import brownie
from datetime import datetime, timedelta
import time

def test_openround_minimal_round_time(accounts, stake2follow):
  with brownie.reverts():
    freezeTime = datetime.now() + timedelta(minutes=1)
    stake2follow.openRound(freezeTime.timestamp())


def test_stake(accounts, stake2follow):
  freezeTime = datetime.now() + timedelta(minutes=30)

  stake2follow.openRound(freezeTime.timestamp(), {'from': accounts[8]})
  stake2follow.profileStake(0x01, accounts[1], {'from': accounts[1]})
  
def test_no_profile_paticipant(accounts, stake2follow):
  freezeTime = datetime.now() + timedelta(minutes=4)
  stake2follow.openRound(freezeTime.timestamp(), {'from': accounts[8]})

  while datetime.now() < freezeTime:
    with brownie.reverts():
      stake2follow.closeRound(0, {'from': accounts[8]})
      time.sleep(30)

  stake2follow.closeRound(0, {'from': accounts[8]})
