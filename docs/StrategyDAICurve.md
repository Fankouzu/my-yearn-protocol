# DAI 策略

- 策略名称:StrategyDAICurve

- [策略合约](../contracts/StrategyDAICurve.sol)

- 合约地址: https://etherscan.io/address/0xAa880345A3147a1fC6889080401C791813ed08Dc#code

- 

## 主要方法
- 存款方法deposit:
    - 获取当前合约在DAI合约中的余额
    - 如果DAI余额>0
        - 将DAI余额的数量批准给iearn DAI (yDAI)
        - 将DAI存款到yDAI合约
    - 获取当前合约的yDAI余额
    - 如果yDAI余额>0
        - 调用yDAI合约的批准方法批准给curve合约,数量为yDAI余额
        - 调用curve合约的添加流动性方法,将yDAI添加到curve合约
    - 获取当前合约的yCrv余额
    - 如果yCrv的余额>0
        - 调用yCrv合约的批准方法批准给yyCrv合约,数量为yCrv余额
        - 调用yyCrv合约的存款,将yCrv存入到yyCrv合约
- 提款方法withdraw:
    - 获取当前合约在DAI合约中的余额
    - 如果DAI余额 < 提款数额
    - 数额 = 赎回DAI资产(数额 - 余额)
        - 计算yCrv数额 = 取款DAI数额 * 1e18 / curve的yCrv虚拟价格
        - 计算yyCrv数额 = yCrv数额 * 1e18 / yyCrv合约中的每份额对应资产数额
        - 在yyCrv平台取款yyCrv的数额,取出的是yCrv
        - 取款底层资产DAI方法,输入资产为yCrv
            - 在yCrv合约中批准curve合约拥有拥有当前合约_amount的数额的控制权
            - 在curve合约中移除流动性,数额为_amount的yCrv
            - 获取yUSDC余额,yUSDT余额,yTUSD余额
            - 如果yUSDC余额 > 0
                - 在yUSDC合约中批准curve合约拥有拥有当前合约_yusdc的数额的控制权
                - 在Curve交易所用yUSDC交换yDAI
            - 如果yUSDT余额 > 0
                - 在yUSDT合约中批准curve合约拥有拥有当前合约_yusdt的数额的控制权
                - 在Curve交易所用yUSDT交换yDAI
            - 如果yTUSD余额 > 0
                - 在yTUSD合约中批准curve合约拥有拥有当前合约_ytusd的数额的控制权
                - 在Curve交易所用yTUSD交换yDAI
            - 调用yDAI合约的取款方法,取出DAI
    - 将数额 - 费用 发送到保险库地址