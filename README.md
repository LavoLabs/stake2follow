# Stake2Follow


## 依赖
### node@v19.7.0

### ganache-cli@v6.12.2

```bash
npm install -g ganache-cli
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

## 编译

```bash
brownie compile
```

## 单元测试

```bash
brownie test
```

## 执行脚本

```bash
brownie run scenario_test
```
