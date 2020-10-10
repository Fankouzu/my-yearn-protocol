# USDC 策略

- 策略名称:StrategyDForceUSDC

- [策略合约](../contracts/StrategyDForceUSDC.sol)

- 合约地址: https://etherscan.io/address/0xA30d1D98C502378ad61Fe71BcDc3a808CF60b897#code

## 主要方法
- 存款方法deposit:
    - 将合约中的USDC发送给dForce: dUSDC Token铸造DToken
    - 再将DToken发送到dForce: Unipool做质押
- 提款方法withdraw:
    - 执行dForce: Unipool的退出方法
    - 提款dUSDC Token到当前账户,并获取奖励(DF Token)
    - 然后执行dUSDC的赎回方法到当前合约,换回USDC
    - 扣除提款费5%,发送USDC给控制器合约的奖励地址
    - 将剩余的USDC发送到`保险库`
- 收获方法harvest:
    - 获取dForce: Unipool的奖励(DF Token)
    - 调用uniswap用精确的token交换尽量多的token方法,用dForce: DF Token换取USDC,发送到当前合约
    - 扣除手续费50%,发送USDC给控制器合约的奖励地址
    - 将剩余的USDC重新进入`存款方法`