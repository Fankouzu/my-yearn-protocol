# curve.fi/y LP保险库合约(yCrv)

- [保险库合约](../contracts/yLPVault.sol)

- 合约地址: https://etherscan.io/address/0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c#code

## 主要方法
- 存款方法deposit:
    - 份额 = 存款数额 * 总量 / 当前合约在yCrv的余额
    - 为调用者铸造份额(当前合约也是erc20合约,在当前合约中铸造数额为`份额`的erc20 Token)
- 赚钱方法earn:
    - 将空闲余额发送到控制器
    - 调用控制器的`赚钱earn`方法,参数为yCrv合约地址和空闲的余额
- 提款方法withdraw:
    - 根据份额计算出用户的取款数额
    - 将份额销毁
    - 如果当前合约的余额不足,需要调用控制器合约的`取款withdraw`方法将yCrv取回到当前合约
    - 将份额对应的取款数额发给用户
