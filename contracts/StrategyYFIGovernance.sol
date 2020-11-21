/**
 *Submitted for verification at Etherscan.io on 2020-09-24
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

//一些接口合约：Governance, yERC20, Uni, ICurveFi, Zap
interface Governance {
    function withdraw(uint256) external;

    function getReward() external;

    function stake(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function exit() external;

    function voteFor(uint256) external;

    function voteAgainst(uint256) external;
}

interface yERC20 {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;
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

interface Zap {
    function remove_liquidity_one_coin(
        uint256,
        int128,
        uint256
    ) external;
}


/**
 *本策略合约操作的资金是YFI；
 *用户角度：在YFI Vault，用户存入YFI代币，获得yYFI代币，赎回yYFI代币时可获取原本投入的YFI代币加上策略赚取的YFI代币；
 *Yearn V2角度：存入的YFI先到YFI Vault中，再到对应的控制器合约中，由控制器合约指定策略合约对defi项目进行投资；
 *本合约是YFI Vault对应的策略合约，策略合约收到YFI后，将YFI stake到yfi gov项目,从而赚取收益;
 *收益来源：yearn v2 机枪池所收到的费用去了专门的国库合约（限额50万美元），超过限额将会自动到治理合约,stake YFI到yfi gov能赚取这部分收益；
 *YFI策略合约 地址:0x395F93350D5102B6139Abfc84a7D6ee70488797C
 */
contract StrategyYFIGovernance {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    //YFI代币地址
    address public constant want = address(
        0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e
    );
    //yearn governance staking 地址 
    address public constant gov = address(
        0xBa37B002AbaFDd8E89a1995dA52740bbC013D992
    );
    //Curve的y池的swap地址
    address public constant curve = address(
        0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51
    );
    //Curve的y池的deposit地址
    address public constant zap = address(
        0xbBC81d23Ea2c3ec7e56D39296F0cbB648873a5d3
    );
    //yCrv Token地址
    address public constant reward = address(
        0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8
    );
    //usdt地址
    address public constant usdt = address(
        0xdAC17F958D2ee523a2206206994597C13D831ec7
    );

    // Uniswap V2: Router 2
    // Uniswao V2 路由2 地址
    address public constant uni = address(
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    );
    //weth 地址
    address public constant weth = address(
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ); 

    //5%的绩效费用
    uint256 public fee = 500;
    //100% 各项费率基准值
    uint256 public constant max = 10000;

    //治理地址:用于治理权限检验
    address public governance;
    //控制器地址:用于与本合约的资金交互
    address public controller;
    //策略管理员地址:用于权限检验和发放策略管理费
    address public strategist;

    /**
     *@dev    构造函数，初始化时调用，部署合约时，只设置一个控制器地址，其他默认为部署地址；
     *@param _controller 控制器地址;
     */
    constructor(address _controller) public {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
    }

    /**
     *@dev 设置费用
     *@param _fee 费用值
     */
    function setFee(uint256 _fee) external {
        //确保合约调用者为治理人员
        require(msg.sender == governance, "!governance");
        fee = _fee;
    }

    /**
     *@dev 设置策略管理员地址
     *@param _strategist 策略管理员地址
     */
    function setStrategist(address _strategist) external {
        //确保合约调用者为治理人员
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }

    /**
     *@dev 存款处理方法 把本合约中的YFI stake到yfi gov中用以赚取stake收益
     */
    function deposit() public {
        //授权yfi gov;
        IERC20(want).safeApprove(gov, 0);
        IERC20(want).safeApprove(gov, IERC20(want).balanceOf(address(this)));
        //把YFI stake 到yfi gov
        Governance(gov).stake(IERC20(want).balanceOf(address(this)));
    }

    /**
     *Controller only function for creating additional rewards from dust
     *@dev 把某token(非YFI)在本合约的余额全部取回到控制器合约
     *@param _asset 某token
     */
    function withdraw(IERC20 _asset) external returns (uint256 balance) {
        //确保是控制器合约调用
        require(msg.sender == controller, "!controller");
        //不能取YFI
        require(want != address(_asset), "want");
        //取余额
        balance = _asset.balanceOf(address(this));
        //发给控制器合约
        _asset.safeTransfer(controller, balance);
    }

    /**
     *Withdraw partial funds, normally used with a vault withdrawal
     *@dev 取款方法，通常是用户从Vault取款时，Vault合约余额不够时触发，赎回数额先到策略合约，再到控制器合约，最后由控制器合约发送至vault合约供用户提取；
     *@param _amount 数额
     */
    function withdraw(uint256 _amount) external {
        //确保是控制器合约调用
        require(msg.sender == controller, "!controller");
        //YFI在本合约的余额
        uint256 _balance = IERC20(want).balanceOf(address(this));
        //如果本合约余额不够
        if (_balance < _amount) {
            //赎回不够的数额
            _amount = _withdrawSome(_amount.sub(_balance));
            //赎回数额加上本合约已有的余额 
            _amount = _amount.add(_balance);
        }
        //计算取款收费
        uint256 _fee = _amount.mul(fee).div(max);
        //将收到的费用发给奖励池，通过控制器合约获取相应的地址
        IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
        //从控制器合约获取vault地址
        address _vault = Controller(controller).vaults(address(want));
        //检验vault地址是否有误
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        //扣除费用后，发送回vault地址
        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
    }

    /**
     *Withdraw all funds, normally used when migrating strategies
     *@dev 全部取款方法，通常是停止策略或者切换策略时调用
     */
    function withdrawAll() external returns (uint256 balance) {
        //确保是控制器合约调用
        require(msg.sender == controller, "!controller");
        //从投资池中，全部赎回
        _withdrawAll();
        //取YFI的全部余额
        balance = IERC20(want).balanceOf(address(this));
        //获取vault地址
        address _vault = Controller(controller).vaults(address(want));
        //检验vault地址是否有误
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        //将全部的YFI发送回vault金库
        IERC20(want).safeTransfer(_vault, balance);
    }

    /**
     *@dev 把yfi gov中的投资全部赎回至本策略合约
     */
    function _withdrawAll() internal {
        Governance(gov).exit();
    }

    /**
     *@dev 收获方法
     *把在yfi gov中奖励的yCrv,先在curve的y池移除流动性换成usdt
     *再在uniswap中把usdt换成weth，weth再换成YFI，YFI继续stake到yfi gov中
     */
    function harvest() public {
        //确保是策略管理员或治理员或交易的发送者调用
        require(
            msg.sender == strategist ||
                msg.sender == governance ||
                msg.sender == tx.origin,
            "!authorized"
        );
        //执行收获操作 从yfi gov收获stake产生的奖励 奖励为yCrv
        Governance(gov).getReward();
        //获取合约中yCrv的余额
        uint256 _balance = IERC20(reward).balanceOf(address(this));
        if (_balance > 0) {
            //授权curve的y池
            IERC20(reward).safeApprove(zap, 0);
            IERC20(reward).safeApprove(zap, _balance);
            //在curve的y池中移除流动性，即yCrv换成usdt
            Zap(zap).remove_liquidity_one_coin(_balance, 2, 0);
        }
        //获取合约中usdt的余额
        _balance = IERC20(usdt).balanceOf(address(this));
        if (_balance > 0) {
            //授权uniswap
            IERC20(usdt).safeApprove(uni, 0);
            IERC20(usdt).safeApprove(uni, _balance);
            //uniswap的兑换路径：usdt兑换weth，weth兑换YFI
            address[] memory path = new address[](3);
            path[0] = usdt;
            path[1] = weth;
            path[2] = want;
            //执行uniswap的兑换方法
            Uni(uni).swapExactTokensForTokens(
                _balance,
                uint256(0),
                path,
                address(this),
                now.add(1800)
            );
        }
        if (IERC20(want).balanceOf(address(this)) > 0) {
            //如果余额还有YFI，继续stake到yfi gov赚取收益;
            deposit();
        }
    }

    
    /**
     *@dev 投资中部分赎回方法
     *param _amount 赎回数量
     */
    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        //把在yfi gov中的投资赎回
        Governance(gov).withdraw(_amount);
        return _amount;
    }


    /**
     *@dev 本合约的YFI余额
     */
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    /**
     *@dev yfi gov的余额
     */
    function balanceOfYGov() public view returns (uint256) {
        return Governance(gov).balanceOf(address(this));
    }

    /**
     *@dev 本合约的YFI余额 加上 yfi gov的余额 等于 管理总量
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfYGov());
    }

    /**
     *@dev 投赞成票
     *@param _proposal 提案
     */
    function voteFor(uint256 _proposal) external {
        //确保是治理地址调用
        require(msg.sender == governance, "!governance");
        Governance(gov).voteFor(_proposal);
    }

    /**
     *@dev 投反对票
     *@param _proposal 提案
     */
    function voteAgainst(uint256 _proposal) external {
        //确保是治理地址调用
        require(msg.sender == governance, "!governance");
        Governance(gov).voteAgainst(_proposal);
    }
    /**
     *@dev 重新设置治理地址
     *@param _governance 治理地址
     */
    function setGovernance(address _governance) external {
        //确保是治理地址调用
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }
    /**
     *@dev 重新设置控制器地址
     *param _controller 控制器地址
     */
    function setController(address _controller) external {
        //确保是治理地址调用
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
}


