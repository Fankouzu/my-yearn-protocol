/**
 *Submitted for verification at Etherscan.io on 2020-09-18
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
/**
* @dev 计算接口
* @notice 调用存款，余额，取款接口
*/
interface Gauge {
    function deposit(uint) external;
    function balanceOf(address) external view returns (uint);
    function withdraw(uint) external;
}
/**
* @dev 铸造接口
* @param 铸造地址
* @notice 外部调用铸造接口
*/
interface Mintr {
    function mint(address) external;
}
/**
* @dev uni接口
* @notice 外部调用uniswap接口，进行swap
*/
interface Uni {
    function swapExactTokensForTokens(uint, uint, address[] calldata, address, uint) external;
}
/**
 * @notice yERC20接口
 */
interface yERC20 {
  function deposit(uint256 _amount) external;
  function withdraw(uint256 _amount) external;
}
/**
 * @notice 使用Curve.fi 接口进行合约操作,将yDAI+yUSDC+yUSDT+yBUSD稳定币进行操作
 */
interface ICurveFi {

  function get_virtual_price() external view returns (uint);
  function add_liquidity(
    uint256[4] calldata amounts,
    uint256 min_mint_amount
  ) external;
  function remove_liquidity_imbalance(
    uint256[4] calldata amounts,
    uint256 max_burn_amount
  ) external;
  function remove_liquidity(
    uint256 _amount,
    uint256[4] calldata amounts
  ) external;
  function exchange(
    int128 from, int128 to, uint256 _from_amount, uint256 _min_to_amount
  ) external;
}
/**
 * @dev 策略接口
 */
interface VoterProxy {
    function withdraw(address _gauge, address _token, uint _amount) external returns (uint);
    function balanceOf(address _gauge) external view returns (uint);
    function withdrawAll(address _gauge, address _token) external returns (uint);
    function deposit(address _gauge, address _token) external;
    function harvest(address _gauge) external;
}
/**
 * @dev curve.fi中的BUSD池子策略
 * @notice 将CRV通过路由换成WETH在换成dai，进行策略投资，获取收益
 */
// curve.fi/busd LP策略合约 地址:0x2EE856843bB65c244F527ad302d6d2853921727e
contract StrategyCurveYBUSDVoterProxy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    // Curve.fi（yDAI+yUSDC+yUSDT+yBUSD）合约地址
    address constant public want = address(0x3B3Ac5386837Dc563660FB6a0937DFAa5924333B);
    address constant public crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);//crv合约地址
    address constant public uni = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);//uni兑换合约
    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // used for crv <> weth <> dai route
    
    address constant public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);//dai合约地址
    address constant public ydai = address(0xC2cB1040220768554cf699b0d863A3cd4324ce32);//ydai合约地址
    address constant public curve = address(0x79a8C46DeA5aDa233ABaFFD40F3A0A2B1e5A4F27);//curve兑换合约
    
    address constant public gauge = address(0x69Fb7c45726cfE2baDeE8317005d3F94bE838840);//流动性挖CRV合约
    address constant public proxy = address(0x5886E475e163f78CF63d6683AbC7fe8516d12081);//策略合约地址
    address constant public voter = address(0xF147b8125d2ef93FB6965Db97D6746952a133934);//CurveYCRVVoter合约

    
    uint public keepCRV = 1000;//保留10%的CRV
    uint constant public keepCRVMax = 10000;//保留最多100%CRV
    
    uint public performanceFee = 500;//5%的绩效费
    uint constant public performanceMax = 10000;//最多100%绩效费
    
    uint public withdrawalFee = 50;//0.5%提现费用
    uint constant public withdrawalMax = 10000;//最大100%提现费用
    
    address public governance;//治理地址
    address public controller;//控制器地址
    address public strategist;//策略管理地址
    
    /**
     * @dev 构造体函数
     * @notice 合约部署的时候，默认创建一个控制器地址，治理地址和策略管理地址均为发送者地址
     */
    constructor(address _controller) public {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
    }
    /**
     * @dev 返回函数
     * @notice 返回策略名称
     */
    function getName() external pure returns (string memory) {
        return "StrategyCurveYBUSDVoterProxy";
    }
    /**
     * @dev 设置策略管理函数
     * @notice 合约部署地址要等于治理地址
     */
    function setStrategist(address _strategist) external {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }
    /**
     * @dev 设置保留CVR的比例
     * @param _keepCRV 保留的CRV
     * @notice 合约部署地址要等于治理地址
     */
    function setKeepCRV(uint _keepCRV) external {
        require(msg.sender == governance, "!governance");
        keepCRV = _keepCRV;
    }
    /**
     * @dev 设置提现费率
     * @param _withdrawalFee 提现费率
     * @notice 合约部署地址要等于治理地址
     */
    function setWithdrawalFee(uint _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        withdrawalFee = _withdrawalFee;
    }
    /**
     * @dev 设置绩效费率
     * @param  _performanceFee 绩效费率
     * @notice 合约部署地址要等于治理地址
     */
    function setPerformanceFee(uint _performanceFee) external {
        require(msg.sender == governance, "!governance");
        performanceFee = _performanceFee;
    }
    /**
     * @dev 存款函数
     * @notice 获取该合约地址在curve中yDAI+yUSDC+yUSDT+yBUSD余额，并发送至proxy合约，调用gauge的存款函数实现盈利
     */
    function deposit() public {
        uint _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            IERC20(want).safeTransfer(proxy, _want);
            VoterProxy(proxy).deposit(gauge, want);
        }
    }
    /**
     * @dev 提现函数
     * @param  _asset 合约
     * @notice 合约部署地址要等于治理地址，控制器才能操作，通常用于提现奖励，到发送者账户
     * @return balance 提现余额
     */
    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        require(msg.sender == controller, "!controller");//控制器调用合约
        require(want != address(_asset), "want");//判断是否为提现存款币种（yDAI+yUSDC+yUSDT+yBUSD）
        require(crv != address(_asset), "crv");//判断是否提现CRV
        require(ydai != address(_asset), "ydai");//判断是否提现yDAI
        require(dai != address(_asset), "dai");//判断是否提现dai
        balance = _asset.balanceOf(address(this));//获取地址余额
        _asset.safeTransfer(controller, balance);//将地址余额发送给控制器
    }
    
    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint _amount) external {
        require(msg.sender == controller, "!controller");//控制器调用
        uint _balance = IERC20(want).balanceOf(address(this));//存款币种在本合约中的余额
        if (_balance < _amount) {//余额小于提现数量
            _amount = _withdrawSome(_amount.sub(_balance));//提现数量为剩下的余额
            _amount = _amount.add(_balance);//将余额加入提现数量中
        }
        
        
        uint _fee = _amount.mul(withdrawalFee).div(withdrawalMax);//计算取款费用
        
        
        IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
        //将奖励发送给控制器合约
        address _vault = Controller(controller).vaults(address(want));//控制器合约获取存款地址
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        //判断该地址是否为0
        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));//扣除费用后将提现数量发送回存款地址
    }
/**
 * @notice 提现全部的投资额，停止策略时使用
 */
    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint balance) {
        require(msg.sender == controller, "!controller");//控制器调用
        _withdrawAll();//取回所有的投资额
        
        
        balance = IERC20(want).balanceOf(address(this));//取回所有的投资额
        
        address _vault = Controller(controller).vaults(address(want));//控制器获取存款地址
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);//将所有的存款发送回原地址
    }
    /**
     * @notice 从投资额中全部取回
     */
    function _withdrawAll() internal {
        VoterProxy(proxy).withdrawAll(gauge, want);
    }
    /**
     * @dev 收获函数
     * @notice 将奖励的CRV换成dai，并使用UNI兑换
     */
    function harvest() public {
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        //判断只有策略管理及治理地址调用
        VoterProxy(proxy).harvest(gauge);//调用proxy合约执行收获
        uint _crv = IERC20(crv).balanceOf(address(this));//获得收获的CRV数量
        if (_crv > 0) {//判断收获的CRV数量是否大于0
            
            uint _keepCRV = _crv.mul(keepCRV).div(keepCRVMax);//计算需要保留的crv
            IERC20(crv).safeTransfer(voter, _keepCRV);//将收获的CRV发送给voter
            _crv = _crv.sub(_keepCRV);//剩下的crv
            
            IERC20(crv).safeApprove(uni, 0);//使用uni授权进行兑换crv
            IERC20(crv).safeApprove(uni, _crv);
            
        
            address[] memory path = new address[](3);//设置uni兑换路径 crv->weth->dai
            path[0] = crv;
            path[1] = weth;
            path[2] = dai;
            
            Uni(uni).swapExactTokensForTokens(_crv, uint(0), path, address(this), now.add(1800));
            //执行uni兑换
        }
        
        uint _dai = IERC20(dai).balanceOf(address(this));//收获dai的余额
        if (_dai > 0) {//判断dai大于0
            IERC20(dai).safeApprove(ydai, 0);//crv兑换成ydai
            IERC20(dai).safeApprove(ydai, _dai);//ydai在兑换成dai
            yERC20(ydai).deposit(_dai);//将dai存入curve池中
        }
        uint _ydai = IERC20(ydai).balanceOf(address(this));
        if (_ydai > 0) {//判断ydai大于0
            IERC20(ydai).safeApprove(curve, 0);
            IERC20(ydai).safeApprove(curve, _ydai);
            ICurveFi(curve).add_liquidity([_ydai,0,0,0],0);//添加流动性到curve，获取yadi收益
        }
        uint _want = IERC20(want).balanceOf(address(this));////收获busd余额
        if (_want > 0) {
            uint _fee = _want.mul(performanceFee).div(performanceMax);//计算绩效费用
            IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);//控制器合约将奖励发给绩效池
            deposit();//继续存入ydai获取收益
        }
    }
    /**
     * @dev 从投资中部分提现方法
     * @param _amount 提现的金额
     */
    function _withdrawSome(uint256 _amount) internal returns (uint) {
        return VoterProxy(proxy).withdraw(gauge, want, _amount);
    }
    /**
     * @dev 获取本合约中ybusd的余额
     */
    function balanceOfWant() public view returns (uint) {
        return IERC20(want).balanceOf(address(this));
    }
    /**
     * @dev 获取本合约中ybusd在proxy的余额
     */
    function balanceOfPool() public view returns (uint) {
        return VoterProxy(proxy).balanceOf(gauge);
    }
    /**
     * @notice pool+want总额
     */
    function balanceOf() public view returns (uint) {
        return balanceOfWant()
               .add(balanceOfPool());
    }
    /**
     * @dev 重新设置治理地址
     * @notice 只有治理地址能使用
     */
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");//合约部署地址调用
        governance = _governance;
    }
    /**
     * @dev 重新设置控制器
     * @notice 只有治理地址能使用
     */
    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");//合约部署地址调用
        controller = _controller;
    }
}