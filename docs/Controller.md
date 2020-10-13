# 控制器合约

- [控制器合约](../contracts/Controller.sol)

- 合约地址: https://etherscan.io/address/0x9e65ad11b299ca0abefc2799ddb6314ef2d91080#code

## 主要方法
- 赚钱方法earn:
    - 输入参数为希望赚到的token地址
    - 调用希望赚到的token对应的策略地址的want地址
    - 如果want地址对应地址不等于token地址
        - 将空闲的余额数量的token发送到转换器
        - 将换后的want发送到策略地址
    - 否则将空闲的余额数量发送到策略合约
    - 最后执行策略合约的`存款deposit`方法
- 提款方法withdraw:
    - 只能由token的保险库合约执行
    - 执行策略合约的`提款withdraw`方法,参数为提款数量
