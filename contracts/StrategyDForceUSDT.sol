/**
 *Submitted for verification at Etherscan.io on 2020-08-13
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.5.17;

import "./common.sol";

/*

 A strategy must implement the following calls;
 
 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()
 
 Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller
 
*/

/*

 策略必须执行以下调用；

 - deposit() 存款
 - withdraw(address) 必须排除yield中使用的所有令牌-Controller角色-withdraw应该返回给Controller
 - withdraw(uint) - 控制器 | 保管箱角色-提款应始终返回保管库
 - withdrawAll() - 控制器 | 保管箱角色-提款应始终返回保管库
 - balanceOf() 查询余额

 在可能的情况下，策略必须保持尽可能不变，而不是更新变量，我们通过在控制器中链接合同来更新合同

*/

interface dRewards {
    function withdraw(uint) external;
    function getReward() external;
    function stake(uint) external;
    function balanceOf(address) external view returns (uint);
    function exit() external;
}

interface dERC20 {
  function mint(address, uint256) external;
  function redeem(address, uint) external;
  function getTokenBalance(address) external view returns (uint);
  function getExchangeRate() external view returns (uint);
}

interface Uni {
    function swapExactTokensForTokens(uint, uint, address[] calldata, address, uint) external;
}

/**
*注解: 小张
**/
/// @title  USDT策略合约 地址:0x787C771035bDE631391ced5C083db424A4A64bD8
contract StrategyDForceUSDT {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    //USDT  Tether USD
    address constant public want = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    //dForce: dUSDT Token
    address constant public d = address(0x868277d475E0e475E38EC5CdA2d9C83B5E1D9fc8);
    //dForce: Unipool 
    address constant public pool = address(0x324EebDAa45829c6A8eE903aFBc7B61AF48538df);
    // dForce: DF Token
    address constant public df = address(0x431ad2ff6a9C365805eBaD47Ee021148d6f7DBe0);
    // Uniswap V2: Router 2 UniSwap路由合约，主要使用其货币兑换方法swapExactTokensForTokens
    address constant public uni = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    //调用Uniswap兑换时，作为中间交易对使用，这样滑点比较小
    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // used for df <> weth <> usdc route
    
    //性能费
    uint public performanceFee = 5000;
    uint constant public performanceMax = 10000;
    //提款手续费
    uint public withdrawalFee = 50;
    uint constant public withdrawalMax = 10000;
    
    //治理地址 0xfeb4acf3df3cdea7399794d0869ef76a6efaff52
    address public governance;
    //控制器合约地址 0x9e65ad11b299ca0abefc2799ddb6314ef2d91080 
    address public controller;
    //策略员地址 0x30084324619d9645019c3f2cb3a94611601a3078
    address public strategist;
    
    ///@dev 构造函数
    ///@param _controller 控制器合约地址
    constructor(address _controller) public {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
    }
    
    ///@notice 得到合约名
    ///@dev 只能外部调用
    function getName() external pure returns (string memory) {
        return "StrategyDForceUSDT";
    }
    
    ///@notice 设置策略员地址
    ///@dev 只能由治理地址设置
    ///@param _strategist 策略员地址
    function setStrategist(address _strategist) external {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }
    
    ///@notice 设置提款手续费
    ///@dev 只能由治理地址设置
    ///@param _withdrawalFee 提款手续费
    function setWithdrawalFee(uint _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        withdrawalFee = _withdrawalFee;
    }
    
    ///@notice 设置性能费
    ///@dev 只能由治理地址设置
    ///@param _performanceFee 性能费
    function setPerformanceFee(uint _performanceFee) external {
        require(msg.sender == governance, "!governance");
        performanceFee = _performanceFee;
    }
    
    ///@notice 将合约中的USDC发送给dForce: dUSDT Token铸造DToken,再将DToken发送到dForce: Unipool做质押
    ///@dev 存款方法
    function deposit() public {
        //USDT余额 = 当前合约在USDT合约中的余额
        uint _want = IERC20(want).balanceOf(address(this));
        //如果USDT余额 > 0
        if (_want > 0) {
            // 将USDC的余额批准给dForce: dUSDT Token
            IERC20(want).safeApprove(d, 0);
            IERC20(want).safeApprove(d, _want);
            // 在dForce: dUSDT Token铸造数额为USDT余额的DToken
            dERC20(d).mint(address(this), _want);
        }
        // dusdt余额 = 当前合约在dusdt合约中的余额
        uint _d = IERC20(d).balanceOf(address(this));
        //如果dusdt余额 > 0
        if (_d > 0) {
            // 将dusdt的余额批准给dForce: Unipool
            IERC20(d).safeApprove(pool, 0);
            IERC20(d).safeApprove(pool, _d);
            // 在dForce: Unipool中质押dusdt的余额
            dRewards(pool).stake(_d);
        }
        
    }
    
    ///@notice 将当前合约在'_asset'资产合约的余额'balance'发送给控制器合约
    ///@dev 提款方法
    ///@param _asset 资产地址
    ///@return balance 当前合约在资产合约中的余额
    // 控制器仅用于从灰尘中产生额外奖励的功能
    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        // 只允许控制器合约调用
        require(msg.sender == controller, "!controller");
        // 资产地址不能等于USDT地址
        require(want != address(_asset), "want");
        // 资产地址不能等于dusdt地址
        require(d != address(_asset), "d");
        // 当前合约在资产合约中的余额
        balance = _asset.balanceOf(address(this));
        // 将资产合约的余额发送给控制器合约
        _asset.safeTransfer(controller, balance);
    }
    
    ///@notice 将当前合约的USDT发送‘_amount’数额给控制器合约的保险库
    ///@dev 提款方法
    ///@param _amount 提现数额
    // 提取部分资金，通常用于金库提取
    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint _amount) external {
        // 只允许控制器合约调用
        require(msg.sender == controller, "!controller");
        // 当前合约的USDT余额
        uint _balance = IERC20(want).balanceOf(address(this));
        //如果 余额 < 提现数额
        if (_balance < _amount) {
            // 数额 = 赎回资产（数额 - 余额）
            _amount = _withdrawSome(_amount.sub(_balance));
            // 数额 += 余额
            _amount = _amount.add(_balance);
        }
        // 提现手续费 提现金额 * 50 / 10000 千分之五 
        uint _fee = _amount.mul(withdrawalFee).div(withdrawalMax);
        
        // 将手续费发送到控制器奖励地址
        IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
        // 保险库 = want合约在控制器的USDT保险库地址
        address _vault = Controller(controller).vaults(address(want));
        // 确保保险库地址不为空
        require(_vault != address(0), "!vault"); 
        // 将USDT 发送到 保险库 
        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
    }

    ///@notice 将当前合约的USDT全部发送给控制器合约的保险库
    ///@dev 提款全部方法
    ///@return balance 当前合约的USDT余额
    //提取所有资金，通常在迁移策略时使用
    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint balance) {
         // 只允许控制器合约调用
        require(msg.sender == controller, "!controller");
        //调用内部全部提款方法
        _withdrawAll();
        //当前合约的USDT余额
        balance = IERC20(want).balanceOf(address(this));
        //保险库 = want合约在控制器的USDT保险库地址
        address _vault = Controller(controller).vaults(address(want));
        //确保保险库地址不为空
        require(_vault != address(0), "!vault"); 
        //将USDT余额全部发送到 保险库 中
        IERC20(want).safeTransfer(_vault, balance);
    }
    
    ///@dev 提款全部方法
    function _withdrawAll() internal {
        //执行dForce: Unipool的退出方法,提款到当前账户,并获取奖励
        dRewards(pool).exit();
        //当前合约的dusdt余额
        uint _d = IERC20(d).balanceOf(address(this));
        //如果余额 > 0
        if (_d > 0) {
            //执行dusdt的赎回方法到当前合约,换取USDT
            dERC20(d).redeem(address(this),_d);
        }
    }
    
    ///@dev 收获方法
    ///@notice
    function harvest() public {
        // 只允许治理地址、策略地址调用
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        //获取dForce: Unipool的奖励
        dRewards(pool).getReward();
        //获取当前合约的dForce: DF Token 余额
        uint _df = IERC20(df).balanceOf(address(this));
        //如果DF余额 > 0 
        if (_df > 0) {
            //将DF的余额批准给uniswap路由合约
            IERC20(df).safeApprove(uni, 0);
            IERC20(df).safeApprove(uni, _df);
            // 交易路径 DF Token => weth => USDT
            address[] memory path = new address[](3);
            path[0] = df;
            path[1] = weth;
            path[2] = want;
            
            //调用uniswap用精确的token交换尽量多的token方法,用dForce: DF Token换取USDT,发送到当前合约
            Uni(uni).swapExactTokensForTokens(_df, uint(0), path, address(this), now.add(1800));
        }

        //获取当前合约的USDT余额
        uint _want = IERC20(want).balanceOf(address(this));
        //如果余额 > 0
        if (_want > 0) {
            // 性能费 = 余额 * 5000/10000 百分之五十
            uint _fee = _want.mul(performanceFee).div(performanceMax);
            //性能费发送到控制器合约的奖励账户中
            IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
            //调用内部 deposit()
            deposit();
        }
    }
    
    ///@notice 根据当前合约在dusdt的余额计算出可以在dusdt中赎回的数额,并赎回资产
    ///@dev 内部赎回资产方法
    ///@param _amount 数额
    ///@return _withdrew 赎回数额
    function _withdrawSome(uint256 _amount) internal returns (uint) {
        // 获得 赎回数额 需要的 dusdt 的交换费
        uint _d = _amount.mul(1e18).div(dERC20(d).getExchangeRate());
        // 获取 _before （当前合约 dusdt 余额）
        uint _before = IERC20(d).balanceOf(address(this));
        // 从dForce: Unipool赎回dusdt
        dRewards(pool).withdraw(_d);
        // 获取 _after （赎回后的 dusdt 余额）
        uint _after = IERC20(d).balanceOf(address(this));
        // 获取 _withdrew （赎回的数额）
        uint _withdrew = _after.sub(_before);
        // 赋值 _before （赎回后的 USDT 余额）
        _before = IERC20(want).balanceOf(address(this));
        // 在dusdt中赎回数额为_withdrew的USDT
        dERC20(d).redeem(address(this), _withdrew);
        // 赋值 _after （赎回后的 USDT 余额）
        _after = IERC20(want).balanceOf(address(this));
        // 赋值 _withdrew（赎回数额） = _after - _before
        _withdrew = _after.sub(_before);
        return _withdrew;
    }
    
    ///@notice 返回当前合约的 USDT 余额
    ///@return USDT 余额
    function balanceOfWant() public view returns (uint) {
        return IERC20(want).balanceOf(address(this));
    }
    
    ///@notice 返回当前合约的在 uniswap pool 中 dusdt 余额
    ///@return uniswap pool 中 dusdt 余额
    function balanceOfPool() public view returns (uint) {
        return (dRewards(pool).balanceOf(address(this))).mul(dERC20(d).getExchangeRate()).div(1e18);
    }
    
    ///@notice 获取dusdt汇率
    ///@return dusdt汇率
    function getExchangeRate() public view returns (uint) {
        return dERC20(d).getExchangeRate();
    }
    
    ///@notice 获取本策略中dusdt的数额
    function balanceOfD() public view returns (uint) {
        return dERC20(d).getTokenBalance(address(this));
    }
    
    ///@notice 本策略管理的总USDT/dusdt数额
    function balanceOf() public view returns (uint) {
        return balanceOfWant()
               .add(balanceOfD())
               .add(balanceOfPool());
    }
    
    ///@notice 设置治理账户地址
    function setGovernance(address _governance) external {
        //只允许治理地址设置
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }
    
    ///@notice 设置控制器合约地址
    function setController(address _controller) external {
        //只允许治理地址设置
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
}