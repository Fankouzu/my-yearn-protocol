/**
 *Submitted for verification at Etherscan.io on 2020-08-13
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.5.17;

import "./common.sol";

/*

 策略必须执行以下调用；

 - deposit() 存款
 - withdraw(address) 必须排除yield中使用的所有令牌-Controller角色-withdraw应该返回给Controller
 - withdraw(uint) - 控制器 | 保管箱角色-提款应始终返回保管库
 - withdrawAll() - 控制器 | 保管箱角色-提款应始终返回保管库
 - balanceOf() 查询余额

 在可能的情况下，策略必须保持尽可能不变，而不是更新变量，我们通过在控制器中链接合同来更新合同


 A strategy must implement the following calls;
 
 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()
 
 Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller
 
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
// USDC策略合约 地址:0xA30d1D98C502378ad61Fe71BcDc3a808CF60b897
contract StrategyDForceUSDC {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    address constant public want = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
    address constant public dusdc = address(0x16c9cF62d8daC4a38FB50Ae5fa5d51E9170F3179); // dForce: dUSDC Token
    address constant public pool = address(0xB71dEFDd6240c45746EC58314a01dd6D833fD3b5); // dForce: Unipool
    address constant public df = address(0x431ad2ff6a9C365805eBaD47Ee021148d6f7DBe0); // dForce: DF Token
    address constant public uni = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D); // Uniswap V2: Router 2
    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // used for df <> weth <> usdc route
    
    uint public performanceFee = 5000;
    uint constant public performanceMax = 10000;
    
    uint public withdrawalFee = 500;
    uint constant public withdrawalMax = 10000;
    
    address public governance; // 0xfeb4acf3df3cdea7399794d0869ef76a6efaff52
    address public controller; // 0x9e65ad11b299ca0abefc2799ddb6314ef2d91080
    address public strategist; // 0x2d407ddb06311396fe14d4b49da5f0471447d45c
    
    /**
     * @dev 构造函数
     * @param _controller 控制器合约地址
     */
    // 0x9e65ad11b299ca0abefc2799ddb6314ef2d91080
    constructor(address _controller) public {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
    }
    
    /**
     * @dev 设置策略员地址
     * @param _strategist 策略员地址
     * @notice 只能由治理地址设置
     */
    // 0x2D407dDb06311396fE14D4b49da5F0471447d45C
    function setStrategist(address _strategist) external {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }
    
    /**
     * @dev 设置提款手续费
     * @param _withdrawalFee 提款手续费
     * @notice 只能由治理地址设置
     */
    function setWithdrawalFee(uint _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        withdrawalFee = _withdrawalFee;
    }
    
    /**
     * @dev 设置性能费
     * @param _performanceFee 性能费
     * @notice 只能由治理地址设置
     */
    function setPerformanceFee(uint _performanceFee) external {
        require(msg.sender == governance, "!governance");
        performanceFee = _performanceFee;
    }
    
    /**
     * @dev 存款方法
     * @notice 将合约中的USDC发送给dForce: dUSDC Token铸造DToken,再将DToken发送到dForce: Unipool做质押
     */
    function deposit() public {
        // USDC余额 = 当前合约在USDC合约中的余额
        uint _want = IERC20(want).balanceOf(address(this));
        // 如果USDC余额 > 0
        if (_want > 0) {
            // 将USDC的余额批准给dForce: dUSDC Token
            IERC20(want).safeApprove(dusdc, 0);
            IERC20(want).safeApprove(dusdc, _want);
            // 在dForce: dUSDC Token铸造数额为USDC余额的DToken
            dERC20(dusdc).mint(address(this), _want);
        }
        // dusdc余额 = 当前合约在dusdc合约中的余额
        uint _dusdc = IERC20(dusdc).balanceOf(address(this));
        // 如果dusdc余额 > 0
        if (_dusdc > 0) {
            // 将dusdc的余额批准给dForce: Unipool
            IERC20(dusdc).safeApprove(pool, 0);
            IERC20(dusdc).safeApprove(pool, _dusdc);
            // 在dForce: Unipool中质押dusdc的余额
            dRewards(pool).stake(_dusdc);
        }
        
    }
    
    /**
     * @dev 提款方法
     * @param _asset 资产地址
     * @notice 将当前合约在_asset资产合约的余额发送给控制器合约
     */
    // 控制器仅用于从灰尘中产生额外奖励的功能
    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        // 只能通过控制器合约调用
        require(msg.sender == controller, "!controller");
        // 资产地址不能等于USDC地址
        require(want != address(_asset), "want");
        // 资产地址不能等于DToken地址
        require(dusdc != address(_asset), "dusdc");
        // 当前合约在资产合约中的余额
        balance = _asset.balanceOf(address(this));
        // 将资产合约的余额发送给控制器合约
        _asset.safeTransfer(controller, balance);
    }
    
    /**
     * @dev 提款方法
     * @param _amount 提款数额
     * @notice 必须从控制器合约调用,将资产赎回,扣除提款费,将提款费发送给控制器合约的奖励地址,再将剩余发送到保险库
     */
    // 提取部分资金，通常用于金库提取
    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint _amount) external {
        // 只能通过控制器合约调用
        require(msg.sender == controller, "!controller");
        // 当前合约在USDC合约中的余额
        uint _balance = IERC20(want).balanceOf(address(this));
        // 如果USDC余额 < 提款数额
        if (_balance < _amount) {
            // 数额 = 赎回资产(数额 - 余额)
            _amount = _withdrawSome(_amount.sub(_balance));
            // 数额 + 余额
            _amount = _amount.add(_balance);
        }
        
        // 费用 = 数额 * 5%
        uint _fee = _amount.mul(withdrawalFee).div(withdrawalMax);
        
        // 将费用发送到控制器奖励地址
        IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
        // 保险库 = want合约在控制器的保险库地址
        address _vault = Controller(controller).vaults(address(want));
        // 将数额 - 费用 发送到保险库地址
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        
        // 将数额 - 费用 发送到保险库地址
        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
    }
    
    /**
     * @dev 提款全部方法
     * @notice 必须从控制器合约调用,将提出的USDC发送到保险库合约
     */
    // 提取所有资金，通常在迁移策略时使用
    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        // 内部提款全部方法
        _withdrawAll();
        
        // 当前合约的USDC余额
        balance = IERC20(want).balanceOf(address(this));
        
        // 保险库合约地址
        address _vault = Controller(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        // 将当前合约的USDC余额发送到保险库合约
        IERC20(want).safeTransfer(_vault, balance);
    }
    
    /**
     * @dev 内部提款全部方法
     * @notice 执行dForce: Unipool的退出方法,提款到当前账户,并获取奖励,然后执行dUSDC的赎回方法到当前合约,换取USDC
     */
    function _withdrawAll() internal {
        // 执行dForce: Unipool的退出方法,提款到当前账户,并获取奖励
        dRewards(pool).exit();
        // 当前合约的dusdc余额
        uint _dusdc = IERC20(dusdc).balanceOf(address(this));
        if (_dusdc > 0) {
            // 执行dusdc的赎回方法到当前合约,换取USDC
            dERC20(dusdc).redeem(address(this),_dusdc);
        }
    }
    
    /**
     * @dev 收获方法
     * @notice 
     */
    function harvest() public {
        // 只能从策略账户或治理账户调用
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        // 获取dForce: Unipool的奖励
        dRewards(pool).getReward();
        // 当前合约的dForce: DF Token的余额
        uint _df = IERC20(df).balanceOf(address(this));
        // 如果dForce: DF Token余额大约0
        if (_df > 0) {
            // 将dForce: DF Token的余额批准给uniswap路由合约
            IERC20(df).safeApprove(uni, 0);
            IERC20(df).safeApprove(uni, _df);
            // 交易路径dForce: DF Token => WETH => USDC
            address[] memory path = new address[](3);
            path[0] = df;
            path[1] = weth;
            path[2] = want;
            
            // 调用uniswap用精确的token交换尽量多的token方法,用dForce: DF Token换取USDC,发送到当前合约
            Uni(uni).swapExactTokensForTokens(_df, uint(0), path, address(this), now.add(1800));
        }
        // 当前合约的USDC余额
        uint _want = IERC20(want).balanceOf(address(this));
        // 如果USDC余额>0
        if (_want > 0) {
            // 手续费 = USDC余额 * 50%
            uint _fee = _want.mul(performanceFee).div(performanceMax);
            // 将手续费发送到奖励地址
            IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
            // 存款方法
            deposit();
        }
    }
    
    /**
     * @dev 赎回资产方法
     * @param _amount 数额
     * @notice 根据当前合约在CToken的余额计算出可以在CToken中赎回的数额,并赎回资产
     */
    function _withdrawSome(uint256 _amount) internal returns (uint) {
        // dusdc余额 = 提款数额 * 1e18 / dusdc的交换比例(0)
        uint _dusdc = _amount.mul(1e18).div(dERC20(dusdc).getExchangeRate());
        // 之前 = 当前合约在dusdc的余额
        uint _before = IERC20(dusdc).balanceOf(address(this));
        // 从dForce: Unipool赎回dusdc
        dRewards(pool).withdraw(_dusdc);
        // 之后 = 当前合约在dusdc的余额
        uint _after = IERC20(dusdc).balanceOf(address(this));
        // 提款数额 = 之后 - 之前
        uint _withdrew = _after.sub(_before);
        // 之前 = 当前合约在USDC的余额
        _before = IERC20(want).balanceOf(address(this));
        // 在dusdc中赎回数量为提款数额的USDC
        dERC20(dusdc).redeem(address(this), _withdrew);
        // 之后 = 当前合约在USDC的余额
        _after = IERC20(want).balanceOf(address(this));
        // 提款数额 = 之后 - 之前
        _withdrew = _after.sub(_before);
        // 返回提款数额
        return _withdrew;
    }
    
    function balanceOfWant() public view returns (uint) {
        return IERC20(want).balanceOf(address(this));
    }
    
    function balanceOfPool() public view returns (uint) {
        return (dRewards(pool).balanceOf(address(this))).mul(dERC20(dusdc).getExchangeRate()).div(1e18);
    }
    
    function getExchangeRate() public view returns (uint) {
        return dERC20(dusdc).getExchangeRate();
    }
    
    function balanceOfDUSDC() public view returns (uint) {
        return dERC20(dusdc).getTokenBalance(address(this));
    }
    
    function balanceOf() public view returns (uint) {
        return balanceOfWant()
               .add(balanceOfDUSDC())
               .add(balanceOfPool());
    }
    
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }
    
    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
}