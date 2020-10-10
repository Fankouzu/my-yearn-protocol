# ETH/WETH 策略

- 策略名称:StrategyMKRVaultDAIDelegate

- [策略合约](../contracts/StrategyMKRVaultDAIDelegate.sol)

- 合约地址: https://etherscan.io/address/0x932fc4fd0eEe66F22f1E23fBA74D7058391c0b15#code

- ETH/WETH 策略的基本原理是将存入的WETH存入到MakerDao中生成Dai,然后将Dai存入到yEarn的yVaultDAI保险库中获利,当yVaultDAI中产生获利之后,又将获利得到的Dai卖出兑换成WETH,循环存入MakerDao中生成Dai;当取出WETH时,根据当前的债务比例调整MakerDao的存款比例,确保债务安全

## 主要方法
- 存款方法deposit:
    - 计算当前合约在WETH合约中的余额
    - 通过预言机获取ETH价格
    - 将ETH余额计算成DAI的数量再取1/2的比例作为准备提取的DAI数量
    - 将准备提取的DAI加上当前债务,计算是否超过债务上限
    - 根据准备提取的DAI数量将WETH锁定,生成DAI
    - 将新生成的DAI,发送给yVaultDAI合约
- 提款方法withdraw:
    - 计算当前合约在WETH合约中的余额
    - 如果余额不够,赎回不够的部分资产
        - 在赎回资产时,如果赎回后MakerDao的Dai债务小于安全值
        - 从yVaultDAI中取出相应数额的Dai然后存入MakerDao以确保债务安全
    - 扣除提款费5%,发送WETH给控制器合约的奖励地址
    - 将剩余的WETH发送到`保险库`
- 收获方法harvest:
    - 获取全部DAI债务数量
    - 获取在yVaultDAI存款的数量
    - 如果存款>债务:
        - 将多余的DAI取出
        - 扣除手续费50%,发送给控制器合约的奖励地址
        - 调用uniswap用精确的token交换尽量多的token方法,用DAI换取WETH,发送到当前合约
    - 将剩余的WETH重新进入`存款方法`