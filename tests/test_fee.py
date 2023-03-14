import brownie

def test_get_fee(accounts, stake2follow):
    assert stake2follow.getGasFee() == 5

def test_only_owner_can_set_fee(accounts, stake2follow):
  stake2follow.setGasFee(20, {'from': accounts[0]})
  with brownie.reverts():
    stake2follow.setGasFee(10, {'from': accounts[1]})

  assert stake2follow.getGasFee() == 20
    
def test_set_fee(accounts, stake2follow):
   assert stake2follow.setGasFee(10, {'from': accounts[0]})
   assert stake2follow.setGasFee(0, {'from': accounts[0]})

   with brownie.reverts():
    stake2follow.setGasFee(110, {'from': accounts[0]})

   with brownie.reverts():
    stake2follow.setGasFee(100, {'from': accounts[0]})
