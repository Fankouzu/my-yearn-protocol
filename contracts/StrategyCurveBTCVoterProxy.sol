/**
 *Submitted for verification at Etherscan.io on 2020-09-21
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
  策略必须执行以下调用：

  -存款（）
  -提款（地址）必须排除在yield中使用的所有令牌-控制器角色-提款应返回给控制器
  -withdraw（uint）-控制器| 保管箱角色-提款应始终返回保管库
  -withdrawAll（）-控制器| 保管箱角色-提款应始终返回保管库
  -balanceOf（）

  在可能的情况下，策略必须保持尽可能不变，而不是更新变量，我们通过在控制器中链接合同来更新合同
*/


/**
 * 使用 Gauge 接口合约进行操作
 */
interface Gauge {
    function deposit(uint) external;
    function balanceOf(address) external view returns (uint);
    function withdraw(uint) external;
}

/**
 * 使用 Mintr 接口合约进行铸币操作
 */
interface Mintr {
    function mint(address) external;
}

/**
 * 使用 Uniswap 接口合约进行兑换操作
 */
interface Uni {
    function swapExactTokensForTokens(uint, uint, address[] calldata, address, uint) external;
}

/**
 * 使用 yERC20 接口合约进行操作
 */
interface yERC20 {
  function deposit(uint256 _amount) external;
  function withdraw(uint256 _amount) external;
}

/**
 * 使用 ICurveFi 接口合约进行操作
 */
interface ICurveFi {
  function get_virtual_price() external view returns (uint);
  function add_liquidity(
    uint256[3] calldata amounts,
    uint256 min_mint_amount
  ) external;
  function remove_liquidity_imbalance(
    uint256[3] calldata amounts,
    uint256 max_burn_amount
  ) external;
  function remove_liquidity(
    uint256 _amount,
    uint256[3] calldata amounts
  ) external;
  function exchange(
    int128 from, int128 to, uint256 _from_amount, uint256 _min_to_amount
  ) external;
}

/**
 * 使用 VoterProxy 接口合约进行操作
 */
interface VoterProxy {
    function withdraw(address _gauge, address _token, uint _amount) external returns (uint);
    function balanceOf(address _gauge) external view returns (uint);
    function withdrawAll(address _gauge, address _token) external returns (uint);
    function deposit(address _gauge, address _token) external;
    function harvest(address _gauge) external;
}
/**
 * @title curve.fi/sbtc  LP策略合约 ；
 * @dev 策略合约地址:0x134c08fAeE4F902999a616e31e0B7e42114aE320
 */
contract StrategyCurveBTCVoterProxy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // Curve.fi renBTC/wBTC/sBTC  crvRenWSBTC合约地址
    address constant public want = address(0x075b1bb99792c9E1041bA13afEf80C91a1e70fB3);
    // Crv Token 代币合约地址
    address constant public crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    // Uniswap v2 版本的路由合约地址，实现兑换功能
    address constant public uni = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    // WETH 地址，实现ETH到WETH代币的转换功能
    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // used for crv <> weth <> dai route
    // WBTC 地址，现在BTC到WBTC代币的转换功能
    address constant public wbtc = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    // Curve.fi: sBTC Swap
    address constant public curve = address(0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714);

    // curve 的流动性挖矿池子，赚取crv
    address constant public gauge = address(0x705350c4BcD35c9441419DdD5d2f097d7a55410F);
    // yEarn StrategyProxy
    address constant public proxy = address(0x5886E475e163f78CF63d6683AbC7fe8516d12081);
    // CurveYCRVVoter
    address constant public voter = address(0xF147b8125d2ef93FB6965Db97D6746952a133934);

    //保留10%的crv
    uint public keepCRV = 1000;
    //用于计算保留比例
    uint constant public keepCRVMax = 10000;
    //5%策略员的收益比例
    uint public performanceFee = 500;
    //用于计算策略员的收益保留比例
    uint constant public performanceMax = 10000;
    //提现手续费
    uint public withdrawalFee = 50;
    //用于计算提现保留比例
    uint constant public withdrawalMax = 10000;
    //治理合约地址
    address public governance;
    //控制器合约地址
    address public controller;
    //策略员地址
    address public strategist;

    /**
     * @dev 构造函数
     * @param _controller 控制器合约地址
     */
    constructor(address _controller) public {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
    }

    /// @notice 获取合约名称
    function getName() external pure returns (string memory) {
        return "StrategyCurveBTCVoterProxy";
    }

    /**
     * @dev 设置策略员地址
     * @param _strategist 策略员地址
     * @notice 只能由治理地址设置
     */
    function setStrategist(address _strategist) external {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }

    /**
     * @dev 设置保留的crv比例
     * @param _keepCRV 比例值
     * @notice 只能由治理地址设置
     */
    function setKeepCRV(uint _keepCRV) external {
        require(msg.sender == governance, "!governance");
        keepCRV = _keepCRV;
    }

    /**
     * @dev 设置提现手续费
     * @param _withdrawalFee 提现手续费
     * @notice 只能由治理地址设置
     */
    function setWithdrawalFee(uint _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        withdrawalFee = _withdrawalFee;
    }

    /**
     * @dev 设置绩效费
     * @param _performanceFee 绩效费
     * @notice 只能由治理地址设置
     */
    function setPerformanceFee(uint _performanceFee) external {
        require(msg.sender == governance, "!governance");
        performanceFee = _performanceFee;
    }

    /**
     * @dev 存款方法
     * @notice 将合约中的crvRenWSBTC发送到控制器合约，控制器合约调用策略合约实现挖矿收益
     */
    function deposit() public {
        // 该合约地址在Curve.fi renBTC/wBTC/sBTC 合约中的余额
        uint _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            // 将余额发送到控制器合约
            IERC20(want).safeTransfer(proxy, _want);
            // 控制器合约调用策略合约中的存钱方法获取挖矿收益
            VoterProxy(proxy).deposit(gauge, want);
        }
    }

    /**
     * @dev 从本合约中提现某种token的全部余额到controller控制器合约
     * @param _asset 代币合约地址
     * @notice 不能提取 want，crv，wbtc
     * @return balance 提现金额
     */
    function withdraw(IERC20 _asset) external returns (uint balance) {
        //仅controller可以操作
        require(msg.sender == controller, "!controller");
        //限定不能提取want，crv，wbtc
        require(want != address(_asset), "want");
        require(crv != address(_asset), "crv");
        require(wbtc != address(_asset), "wbtc");
        //获取对应token的余额
        balance = _asset.balanceOf(address(this));
        //转账给controller合约
        _asset.safeTransfer(controller, balance);
    }
    /**
     * @dev yCRV提现
     * @param _amount 提现金额
     * @notice 仅controller可以操作，提取部分资金，通常用于撤消金库
     */
    function withdraw(uint _amount) external {
        //仅controller合约地址可以操作
        require(msg.sender == controller, "!controller");
        // 获取合约中yCRV的数量
        uint _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            //计算差额并提取
            _amount = _withdrawSome(_amount.sub(_balance));
            //重新计算提取金额，防止提取的差额错误
            _amount = _amount.add(_balance);
        }
        // 提现手续费 _fee = _amount * 0.05
        uint _fee = _amount.mul(withdrawalFee).div(withdrawalMax);
        // 把手续费发送到controller里设置的奖励地址
        IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
        // 获取保险库地址
        address _vault = Controller(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        // 扣除手续费后,剩余yCRV打入保险库中
        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
        
        
    }

    /**
     * @dev 取款函数
     * @notice 取出所有yCRV,一般用在迁移策略的时候
     */
    function withdrawAll() external returns (uint balance) {
        //仅controller可以操作
        require(msg.sender == controller, "!controller");
        //调用内部私有方法提现
        _withdrawAll();

        // 本合约中所有yCRV的数量
        balance = IERC20(want).balanceOf(address(this));
        // 获取保险库合约地址
        address _vault = Controller(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        // yCRV打入保险库中
        IERC20(want).safeTransfer(_vault, balance);
        
    }

    /**
     * @dev 内部调用提现函数
     * @notice 从curve的gauge策略合约中取出所有yCRV
     */
    function _withdrawAll() internal {
        uint _before = balanceOf();
        VoterProxy(proxy).withdrawAll(gauge, want);
        require(_before == balanceOf(), "!slippage");
    }

    /**
     * @dev 收获方法
     * @notice 获取crv收益，兑换为ycrv，再存入curve的gauge中再获取收益
     */
    function harvest() public {
        // 只能从策略账户或治理账户调用
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        // 通过 VoterProxy 代理合约调用curve的gauge合约获取crv收益
        VoterProxy(proxy).harvest(gauge);
        //当前合约的crv余额
        uint _crv = IERC20(crv).balanceOf(address(this));
        if (_crv > 0) {
            //10%的crv转给voter保险库合约地址， 0.1=1000/10000
            uint _keepCRV = _crv.mul(keepCRV).div(keepCRVMax);
            IERC20(crv).safeTransfer(voter, _keepCRV);
            //计算剩余crv
            _crv = _crv.sub(_keepCRV);

            //授权给uni对应的_crv数量
            IERC20(crv).safeApprove(uni, 0);
            IERC20(crv).safeApprove(uni, _crv);

            //定义路径 crv->weth->wbtc
            address[] memory path = new address[](3);
            path[0] = crv;
            path[1] = weth;
            path[2] = wbtc;

            //执行uni的兑换方法
            Uni(uni).swapExactTokensForTokens(_crv, uint(0), path, address(this), now.add(1800));
        }
        //获取本合约中wbtc余额
        uint _wbtc = IERC20(wbtc).balanceOf(address(this));
        if (_wbtc > 0) {
            //授权给curve合约
            IERC20(wbtc).safeApprove(curve, 0);
            IERC20(wbtc).safeApprove(curve, _wbtc);
            //向curve合约提供流动性获取ycrv代币
            ICurveFi(curve).add_liquidity([0,_wbtc,0],0);
        }
        //获取本合约中ycrv余额
        uint _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            // 计算策略费 0.05%=500/10000
            uint _fee = _want.mul(performanceFee).div(performanceMax);
            // 把策略费转到controller中设置的奖励池中
            IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
            //将此次获取的ycrv再次进行存款操作，获取crv收益
            deposit();
        }
    }

    /**
     * @dev 从投资中部分提现方法
     * @param _amount 提现的金额
     * @notice
     */
    function _withdrawSome(uint256 _amount) internal returns (uint) {
        return VoterProxy(proxy).withdraw(gauge, want, _amount);
    }

    /**
     * @dev 获取本合约中ycrv的余额
     * @notice
     */
    function balanceOfWant() public view returns (uint) {
        return IERC20(want).balanceOf(address(this));
    }

    /**
     * @dev proxy在gauge中的ycrv余额
     * @notice
     */
    function balanceOfPool() public view returns (uint) {
        return VoterProxy(proxy).balanceOf(gauge);
    }

    /**
     * @dev 获取余额（合约中ycrv的余额+proxy在gauge中的ycrv余额）
     * @notice
     */
    function balanceOf() public view returns (uint) {
        return balanceOfWant()
               .add(balanceOfPool());
    }

    /**
     * @dev 设置治理地址 仅限原有治理地址调用
     * @notice
     */
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    /**
     * @dev 设置控制器地址 仅限原有治理地址调用
     * @notice
     */
    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
}