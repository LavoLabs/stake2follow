# Stake2Follow

This is the contract codes for Stake2Follow dApp of [Lens Protocol](https://www.lens.xyz/)


## Requirements 
### node@v19.7.0

### ganache-cli@v6.12.2

```bash
npm install -g ganache-cli
```
Note, windows should set PATH variable:

```
set PATH=C:\Users\[user name]\AppData\Roaming\npm;%PATH%
```

### pipx Python@3.10.9

```bash
python -m pip install --user pipx
python -m pipx ensurepath
```
### brownie@v1.19.3

```bash
pipx install eth-brownie
```

### OpenZeppelin-contracts@4.5.0

```bash
brownie pm install OpenZeppelin/openzeppelin-contracts@4.5.0
```

### brownie-token-tester

```bash
pipx inject eth-brownie brownie-token-tester
```

## Compile

```bash
brownie compile
```

## Unitest

```bash
brownie test
```

## Run test

```bash
brownie run scenario_test
```

## setup mumbai testnet

https://wiki.polygon.technology/docs/develop/alchemy/
https://github.com/curvefi/brownie-tutorial/tree/main/lesson-14-networks

### add network
```
brownie networks add Ethereum matic_mumbai chainid=8001 explorer=https://mumbai.polygonscan.com/ name=MATIC host=https://polygon-mumbai.g.alchemy.com/v2/your-api-key
```

### create local account
```
>>> account = accounts.add()
mnemonic: 'behind cliff evoke drum want device output depth track wait truck gift'
>>> account.private_key
'0x8c4c8ef409543fe09837da154be27cd79a1f8617cbdbe4e4f14858ce826dd173'
>>> account.public_key
'0x1eec07922ae7a69018c7fcf0b09b7a1f67c074a18fa42c5ed6dcfe183448d830a12663dc1ec6bda154d0872e3d2d6732d3b7b63c2f74bfffd768425c7d933118'
>>> account.save('lens-test-mumbai')
Enter the password to encrypt this account with: 
'C:\\Users\\xuxiang\\.brownie\\accounts\\lens-test-mumbai.json'
```
### import json to metamask

### or export private keys from metamask

```
3be1c6c28113bdb813c167be5d378d88f8efb388a1a80d1f8aca69ab832a46cf
ae58ff18f48099edd126cb559ca0022264f34f732a1021bf59b6618ab4206ffa
8c4c8ef409543fe09837da154be27cd79a1f8617cbdbe4e4f14858ce826dd173
```


```
from scripts.deploy_contract import *
```


### public source

```
stake2Follow.get_verification_info()['standard_json_input']
```
