pragma solidity ^0.5.17;

import "@openzeppelinV2/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV2/contracts/math/SafeMath.sol";
import "@openzeppelinV2/contracts/utils/Address.sol";
import "@openzeppelinV2/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/yearn/IController.sol";
import "../../interfaces/curve/Gauge.sol";
import "../../interfaces/curve/Mintr.sol";
import "../../interfaces/uniswap/Uni.sol";
import "../../interfaces/curve/Curve.sol";
import "../../interfaces/yearn/IToken.sol";
import "../../interfaces/yearn/IVoterProxy.sol";

/**
* Curve项目的Compound池 策略合约
*、对应的保险柜是cDai+cUSDC
*https://www.curve.fi/compound
* 
*注解：lucas
*/
contract StrategyCurveCompoundVoterProxy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // Curve.fi cDAI/cUSDC (cDAI+cUSDC)   合约地址
    //cDAI  由Compound存入DAI时生成
    //cUSDC 由Compound存入USDC时生成
    //cDAI+cUSDC 是Curve存入DAI和USDC的交易池，Curve会连接Compound分别生成cDAI和cUSDC
    //本策略操作的资金是cDAI+cUSD
    address public constant want = address(0x845838DF265Dcd2c412A1Dc9e959c7d08537f8a2);
    //Crv Token合约地址
    address public constant crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    //UniswapV2Router02 UniSwap路由合约，主要使用其货币兑换方法swapExactTokensForTokens
    address public constant uni = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    //调用Uniswap兑换时，作为中间交易对使用，这样滑点比较小
    address public constant weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // used for crv <> weth <> dai route
    //DAI token地址
    address public constant dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    //Cureve的主合约 ，主要用于将获得的crv兑换处的dai，又通过添加流动性的方式获得cDAI+cUSD
    address public constant curve = address(0xA2B47E3D5c44877cca798226B7B8118F9BFb7A56);
    //gauge类似其他项目的二池，存入cDAI+cUSDC挖crv
    address public constant gauge = address(0x7ca5b0a2910B33e9759DC7dDB0413949071D7575);
    //CurveYCRVVoter
    address public constant voter = address(0xF147b8125d2ef93FB6965Db97D6746952a133934);

    uint256 public keepCRV = 1500;                //保留15%的crv
    uint256 public performanceFee = 450;          //4.5%绩效费
    uint256 public strategistReward = 50;         //0.5%的管理费
    uint256 public withdrawalFee = 0;             //取款费，暂时没收
    uint256 public constant FEE_DENOMINATOR = 10000; //各项费率基准值

    //yearn IVoterProxy 策略资金操作代理，封装了存款，取款等投资方法
    address public proxy;

    address public governance;    //治理地址----主要用于治理权限检验
    address public controller;    //控制器地址-----主要用于与本合约的资金交互
    address public strategist;    //策略管理员地址-----主要用于权限检验和发放策略管理费

    uint256 public earned; // lifetime strategy earnings denominated in `want` token
    //定义收获事件
    event Harvested(uint256 wantEarned, uint256 lifetimeEarned);

    //部署合约时，只设置一个控制器地址，其他默认为部署地址
    constructor(address _controller) public {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
    }

    //返回策略名称
    function getName() external pure returns (string memory) {
        return "StrategyCurveCompoundVoterProxy";
    }

    //设置管理员地址
    function setStrategist(address _strategist) external {
        require(msg.sender == governance || msg.sender == strategist, "!authorized");
        strategist = _strategist;
    }

    //设置保留的crv比例
    function setKeepCRV(uint256 _keepCRV) external {
        require(msg.sender == governance, "!governance");
        keepCRV = _keepCRV;
    }

    //设置取款费率
    function setWithdrawalFee(uint256 _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        withdrawalFee = _withdrawalFee;
    }

    //设置绩效费率
    function setPerformanceFee(uint256 _performanceFee) external {
        require(msg.sender == governance, "!governance");
        performanceFee = _performanceFee;
    }

    //设置策略管理员费率
    function setStrategistReward(uint256 _strategistReward) external {
        require(msg.sender == governance, "!governance");
        strategistReward = _strategistReward;
    }

    function setProxy(address _proxy) external {
        require(msg.sender == governance, "!governance");
        proxy = _proxy;
    }

    //存款后的进一步处理
    //调用路径 vault合约的earn方法-----》controller合约的earn方法
    function deposit() public {
        //本鹤羽丹的 cDAI/cUSDC 余额
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            //将余额发送到proxy合约, 
            IERC20(want).safeTransfer(proxy, _want);
            //通过proxy合约，最终执行gauge的deposit方法
            IVoterProxy(proxy).deposit(gauge, want);
        }
    }

    //把某一个token在本合约的余额全部取回到controller控制器合约
    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint256 balance) {
        //只能由控制器合约调用
        require(msg.sender == controller, "!controller");
        //限定：不能取cDAI/cUSDC
        require(want != address(_asset), "want");
        //限定：不能取crv
        require(crv != address(_asset), "crv");
        //限定： 不能取dai
        require(dai != address(_asset), "dai");
        //取余额
        balance = _asset.balanceOf(address(this));
        //发给控制器合约
        _asset.safeTransfer(controller, balance);
    }

    //取款方法，通常是用户从Vault取款时，Vault合约余额不够时触发
    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint256 _amount) external {
        //限定：只能由控制器合约调用
        require(msg.sender == controller, "!controller");
        //cDAI/cUSDC在本合约的余额
        uint256 _balance = IERC20(want).balanceOf(address(this));
        //如果本合约的余额还是不够
        if (_balance < _amount) {
            //赎回还差的金额
            _amount = _withdrawSome(_amount.sub(_balance));
            //实际赎回金额 + balance = 真实的用金额
            _amount = _amount.add(_balance);
        }
        //计算取款收费
        uint256 _fee = _amount.mul(withdrawalFee).div(FEE_DENOMINATOR);
        //将收到费发给奖励池-----通过controller获取相应的地址
        IERC20(want).safeTransfer(IController(controller).rewards(), _fee);
        //从控制器合约获取保险柜地址
        address _vault = IController(controller).vaults(address(want));
        //检验保险地址是否有误
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        //扣除费用后，发送回保险柜地址
        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
    }

    //从投资中部分赎回方法
    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        return IVoterProxy(proxy).withdraw(gauge, want, _amount);
    }

    //全部取款方法，通常是停止策略或者切换策略时调用
    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint256 balance) {
        //限定只能控制器合约调用
        require(msg.sender == controller, "!controller");
        //从投资池中，全部赎回
        _withdrawAll();
        //取cDAI/cUSDC的全部余额
        balance = IERC20(want).balanceOf(address(this));
        //获取保险柜地址
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        //将全部的cDAI/cUSDC发送回保险柜
        IERC20(want).safeTransfer(_vault, balance);
    }

    //从投资中全部赎回
    function _withdrawAll() internal {
        IVoterProxy(proxy).withdrawAll(gauge, want);
    }

    //收获方法，只能由策略管理员和治理地址调用
    //主要是将奖励的crv换成dai，然后再投资到curve流动性池子中
    function harvest() public {
        //限定：只能由策略管理员和治理地址调用
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        //执行收获操作
        IVoterProxy(proxy).harvest(gauge);
        //收获CRV
        uint256 _crv = IERC20(crv).balanceOf(address(this));
        if (_crv > 0) {
            //保留一部分crv，并发送给voter
            uint256 _keepCRV = _crv.mul(keepCRV).div(FEE_DENOMINATOR);
            IERC20(crv).safeTransfer(voter, _keepCRV);
            //剩余的crv
            _crv = _crv.sub(_keepCRV);
            //授权uni，开始将crv换为weth，再换为dai
            IERC20(crv).safeApprove(uni, 0);
            IERC20(crv).safeApprove(uni, _crv);
            //填充uni的兑换路径
            address[] memory path = new address[](3);
            path[0] = crv;
            path[1] = weth;
            path[2] = dai;
            //执行uni的兑换方法
            Uni(uni).swapExactTokensForTokens(_crv, uint256(0), path, address(this), now.add(1800));
        }

        //收获dai------这些dai主要是奖励的crv换来的
        uint256 _dai = IERC20(dai).balanceOf(address(this));
        if (_dai > 0) {
            IERC20(dai).safeApprove(curve, 0);
            IERC20(dai).safeApprove(curve, _dai);
            //添加流动性到curve 将dai又变成cDAI/cUSDC
            ICurveFi(curve).add_liquidity([_dai, 0, 0], 0);
        }
        //收获cDAI/cUSDC
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            //计算绩效费
            uint256 _fee = _want.mul(performanceFee).div(FEE_DENOMINATOR);
            //计算管理费
            uint256 _reward = _want.mul(strategistReward).div(FEE_DENOMINATOR);
            //将绩效费发送给绩效池
            IERC20(want).safeTransfer(IController(controller).rewards(), _fee);
            //将管理费发送给策略管理员
            IERC20(want).safeTransfer(strategist, _reward);
            deposit();
        }
        IVoterProxy(proxy).lock();
        //增加赚钱金额
        earned = earned.add(_want);
        //发送收获消息事件
        emit Harvested(_want, earned);
    }

    //本合约的cDAI+cUSDC余额
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    //投资中cDAI/cUSDC金额
    function balanceOfPool() public view returns (uint256) {
        return IVoterProxy(proxy).balanceOf(gauge);
    }

    //本策略管理的总cDAI/cUSDC金额
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    //重新设置治理地址------仅限原有治理地址调用
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    //重新设置控制器地址，-----仅限治理地址调用
    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
}
