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
