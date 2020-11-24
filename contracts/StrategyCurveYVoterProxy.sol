/**
 *Submitted for verification at Etherscan.io on 2020-09-22
 */

// SPDX-License-Identifier: MIT

pragma solidity ^0.5.17;

import "./common.sol";

/*

 策略必须实现以下接口；

 - deposit() 存款
 - withdraw(address) 必须排除yield中所有代币-Controller角色-withdraw账号应该为Controller合约账号
 - withdraw(uint) - 控制器 | 保管箱角色-withdraw账号应该为保管库合约账号
 - withdrawAll() - 控制器 | 保管箱角色-withdraw账号应该为保管库合约账号
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

interface Gauge {
    function deposit(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function withdraw(uint256) external;
}

interface Mintr {
    function mint(address) external;
}

interface Uni {
    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external;
}

interface yERC20 {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;
}

interface ICurveFi {
    function get_virtual_price() external view returns (uint256);

    function add_liquidity(uint256[4] calldata amounts, uint256 min_mint_amount)
    external;

    function remove_liquidity_imbalance(
        uint256[4] calldata amounts,
        uint256 max_burn_amount
    ) external;

    function remove_liquidity(uint256 _amount, uint256[4] calldata amounts)
    external;

    function exchange(
        int128 from,
        int128 to,
        uint256 _from_amount,
        uint256 _min_to_amount
    ) external;
}

interface VoterProxy {
    function withdraw(
        address _gauge,
        address _token,
        uint256 _amount
    ) external returns (uint256);

    function balanceOf(address _gauge) external view returns (uint256);

    function withdrawAll(address _gauge, address _token)
    external
    returns (uint256);

    function deposit(address _gauge, address _token) external;

    function harvest(address _gauge) external;
}

/**
 * @title curve.fi/y LP策略合约
 * @author 噷崖
 * @dev  地址:0x594a198048501A304267E63B3bAd0f0638da7628
 */
contract StrategyCurveYVoterProxy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // yCRV地址 Curve.fi yDAI/yUSDC/yUSDT/yTUSD (yDAI+yUSDC+yUSDT+yTUSD)  yCRV可以理解为4种稳定币的指标
    address public constant want = address(
        0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8
    );
    // Curve DAO Token (CRV)
    address public constant crv = address(
        0xD533a949740bb3306d119CC777fa900bA034cd52
    );
    // Uniswap V2: Router 2
    address public constant uni = address(
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    );
    // WETH
    address public constant weth = address(
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ); // used for crv <> weth <> dai route
    // Dai Stablecoin (DAI)
    address public constant dai = address(
        0x6B175474E89094C44Da98b954EedeAC495271d0F
    );
    // iearn DAI (yDAI)
    address public constant ydai = address(
        0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01
    );
    // Curve.fi: y Swap
    address public constant curve = address(
        0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51
    );
    // Curve.fi: yCrv Gauge
    address public constant gauge = address(
        0xFA712EE4788C042e2B7BB55E6cb8ec569C4530c1
    );
    // yEarn StrategyProxy
    address public constant proxy = address(
        0x5886E475e163f78CF63d6683AbC7fe8516d12081
    );
    // yEarn CurveYCRVVoter
    address public constant voter = address(
        0xF147b8125d2ef93FB6965Db97D6746952a133934
    );

    uint256 public keepCRV = 1000;  //保留的crv比例，可以由governance修改
    uint256 public constant keepCRVMax = 10000; //用于计算保留比例

    uint256 public performanceFee = 500; //策略员的收益比例
    uint256 public constant performanceMax = 10000;//用于计算策略员的收益比例

    uint256 public withdrawalFee = 50;//提现手续费
    uint256 public constant withdrawalMax = 10000;//用于计算提现手续费

    address public governance; //治理地址 0x2D407dDb06311396fE14D4b49da5F0471447d45C
    address public controller; //控制器 0x9E65Ad11b299CA0Abefc2799dDB6314Ef2d91080
    address public strategist; //策略员地址 0x2D407dDb06311396fE14D4b49da5F0471447d45C

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

    /// @notice 获取合约名称
    function getName() external pure returns (string memory) {
        return "StrategyCurveYVoterProxy";
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
    * @dev 设置保留的crv比例
    * @param _keepCRV 比例值
    * @notice 只能由治理地址设置
    */
    function setKeepCRV(uint256 _keepCRV) external {
        require(msg.sender == governance, "!governance");
        keepCRV = _keepCRV;
    }

    /**
     * @dev 设置提现手续费
     * @param _withdrawalFee 提现手续费
     * @notice 只能由治理地址设置
     */
    function setWithdrawalFee(uint256 _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        withdrawalFee = _withdrawalFee;
    }

    /**
     * @dev 设置性能费
     * @param _performanceFee 性能费
     * @notice 只能由治理地址设置
     */
    function setPerformanceFee(uint256 _performanceFee) external {
        require(msg.sender == governance, "!governance");
        performanceFee = _performanceFee;
    }

    /**
     * @dev 存款方法
     * @notice 将本合约中的ycrv通过proxy合约存入gauge中获取收益
     */
    function deposit() public {
        // 当前合约在yCrv合约中的余额
        uint256 _want = IERC20(want).balanceOf(address(this));
        // 如果余额大于0
        if (_want > 0) {
            // 将yCrv余额批准给yEarn StrategyProxy
            IERC20(want).safeTransfer(proxy, _want);
            // 通过proxy合约存入gauge中获取收益
            VoterProxy(proxy).deposit(gauge, want);
        }
    }

    /**
     * @dev 从本合约中提现某种token的全部余额到controller控制器合约
     * @param _asset 代币合约地址
     * @notice 不能提取 want，crv，ydai，dai
     * @return balance 提现金额
     */
    function withdraw(IERC20 _asset) external returns (uint256 balance) {
        //仅controller可以操作
        require(msg.sender == controller, "!controller");
        //限定不能提取want，crv，ydai，dai
        require(want != address(_asset), "want");
        require(crv != address(_asset), "crv");
        require(ydai != address(_asset), "ydai");
        require(dai != address(_asset), "dai");
        //获取对应token的余额
        balance = _asset.balanceOf(address(this));
        //转账给controller
        _asset.safeTransfer(controller, balance);
    }

    /**
     * @dev yCRV提现
     * @param _amount 提现金额
     * @notice 仅controller可以操作
     */
    function withdraw(uint256 _amount) external {
        //仅controller可以操作
        require(msg.sender == controller, "!controller");
        // 获取合约中yCRV的数量
        uint256 _balance = IERC20(want).balanceOf(address(this));
        // 如果合约中yCRV的数量小于提现金额,差额需要去curve的gauge中取回
        if (_balance < _amount) {
            //计算差额并提取
            _amount = _withdrawSome(_amount.sub(_balance));
            //重新计算提取金额，防止提取的差额错误
            _amount = _amount.add(_balance);
        }

        // 提现手续费 _fee = _amount * 0.05
        uint256 _fee = _amount.mul(withdrawalFee).div(withdrawalMax);
        // 把手续费发送到controller里设置的奖励地址
        IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
        // 获取保险库地址
        address _vault = Controller(controller).vaults(address(want));
        //判断获取的保险库地址是否有效  additional protection so we don't burn the funds
        require(_vault != address(0), "!vault");
        // 扣除手续费后,剩余yCRV打入保险库中
        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
    }

    /**
     * @dev 取款函数
     * @notice 取出所有yCRV,一般用在迁移策略的时候 Withdraw all funds, normally used when migrating strategies
     */
    function withdrawAll() external returns (uint256 balance) {
        //仅controller可以操作
        require(msg.sender == controller, "!controller");
        //调用内部提现
        _withdrawAll();

        // 本合约中所有yCRV的数量
        balance = IERC20(want).balanceOf(address(this));
        // 获取保险库地址 0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c
        address _vault = Controller(controller).vaults(address(want));
        //判断获取的保险库地址是否有效  additional protection so we don't burn the funds
        require(_vault != address(0), "!vault");
        // yCRV打入保险库中
        IERC20(want).safeTransfer(_vault, balance);
    }

    /**
     * @dev 内部调用提现函数
     * @notice 从curve的gauge中取出所有yCRV
     */
    function _withdrawAll() internal {
        // 从y池 gauge中取出该合约所拥有的所有yCRV
        VoterProxy(proxy).withdrawAll(gauge, want);
    }

    /**
     * @dev 收获方法
     * @notice 获取crv收益，兑换为ycrv，再存入curve的gauge中再获取收益
     */
    function harvest() public {
        // 只能从策略账户或治理账户调用
        require(
            msg.sender == strategist || msg.sender == governance,
            "!authorized"
        );
        // 通过 VoterProxy 代理合约调用curve的gauge合约获取crv收益
        VoterProxy(proxy).harvest(gauge);
        //当前合约的crv余额
        uint256 _crv = IERC20(crv).balanceOf(address(this));
        //如果当前合约的crv余额大于0
        if (_crv > 0) {
            //10%的crv转给voter， 0.1=1000/10000
            uint256 _keepCRV = _crv.mul(keepCRV).div(keepCRVMax);
            IERC20(crv).safeTransfer(voter, _keepCRV);
            //计算剩余crv
            _crv = _crv.sub(_keepCRV);

            //授权给uni对应的_crv数量
            IERC20(crv).safeApprove(uni, 0);
            IERC20(crv).safeApprove(uni, _crv);

            //定义路径 crv->weth->dai
            address[] memory path = new address[](3);
            path[0] = crv;
            path[1] = weth;
            path[2] = dai;

            //执行uni的兑换方法
            Uni(uni).swapExactTokensForTokens(
                _crv,
                uint256(0),
                path,
                address(this),
                now.add(1800)
            );
        }
        //获取本合约中dai余额
        uint256 _dai = IERC20(dai).balanceOf(address(this));
        if (_dai > 0) {
            //授权给ydai合约
            IERC20(dai).safeApprove(ydai, 0);
            IERC20(dai).safeApprove(ydai, _dai);
            //存款到ydai合约中换取ydai
            yERC20(ydai).deposit(_dai);
        }
        //获取本合约中ydai余额
        uint256 _ydai = IERC20(ydai).balanceOf(address(this));
        if (_ydai > 0) {
            //授权给curve合约
            IERC20(ydai).safeApprove(curve, 0);
            IERC20(ydai).safeApprove(curve, _ydai);
            //向curve合约提供流动性获取ycrv代币
            ICurveFi(curve).add_liquidity([_ydai, 0, 0, 0], 0);
        }
        //获取本合约中ycrv余额
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            // 计算策略费 0.05%=500/10000
            uint256 _fee = _want.mul(performanceFee).div(performanceMax);
            // 把策略费转到controller中设置的奖励池中
            IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
            //讲此次获取的ycrv再次进行存款操作，获取crv收益
            deposit();
        }
    }

    /**
     * @dev 从投资中部分提现方法
     * @param _amount 提现的金额
     * @notice
     */
    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        return VoterProxy(proxy).withdraw(gauge, want, _amount);
    }

    /**
     * @dev 获取本合约中ycrv的余额
     * @notice
     */
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    /**
     * @dev proxy在gauge中的ycrv余额
     * @notice
     */
    function balanceOfPool() public view returns (uint256) {
        return VoterProxy(proxy).balanceOf(gauge);
    }

    /**
     * @dev 获取余额（合约中ycrv的余额+proxy在gauge中的ycrv余额）
     * @notice
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
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
