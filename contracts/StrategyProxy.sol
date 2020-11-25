// SPDX-License-Identifier: MIT

pragma solidity ^0.5.17;

import "@openzeppelinV2/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV2/contracts/math/SafeMath.sol";
import "@openzeppelinV2/contracts/utils/Address.sol";
import "@openzeppelinV2/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/yearn/IProxy.sol";
import "../../interfaces/curve/Mintr.sol";

/**
*本合约功能：
* 1、Curve 调用接口封装deposit，withdraw，harvest三个方法
* 2、策略的审核approveStrategy，revokeStrategy，要求功能1调用的策略必须是经过审核的
* Lucas
*/
contract StrategyProxy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    //CurveYCRVVoter 合约
    IProxy public constant proxy = IProxy(0xF147b8125d2ef93FB6965Db97D6746952a133934);
    //Curve Token Minter 用于Crv的分发挖矿
    address public constant mintr = address(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0);
    //crv token
    address public constant crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    //Curve的gauge facotry，所有gauge都汇总在此
    address public constant gauge = address(0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB);
    //Curve（本合约未使用）
    address public constant y = address(0xFA712EE4788C042e2B7BB55E6cb8ec569C4530c1);
    //策略的审核结果
    mapping(address => bool) public strategies;
    //治理地址
    address public governance;

    constructor() public {
        governance = msg.sender;
    }

    //设置治理地址
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    //允许策略
    function approveStrategy(address _strategy) external {
        require(msg.sender == governance, "!governance");
        strategies[_strategy] = true;
    }

    //禁止策略
    function revokeStrategy(address _strategy) external {
        require(msg.sender == governance, "!governance");
        strategies[_strategy] = false;
    }

    function lock() external {
        //CurveYCRVVoter合约的Crv
        uint256 amount = IERC20(crv).balanceOf(address(proxy));
        //增加托管合约中crv的托管金额
        if (amount > 0) proxy.increaseAmount(amount);
    }

    //参与Curve的治理（调整池子各个币种的比例？）
    function vote(address _gauge, uint256 _amount) public {
        require(strategies[msg.sender], "!strategy");
        //所有资金都在proxy，因此还得通过代理去调用
        proxy.execute(gauge, 0, abi.encodeWithSignature("vote_for_gauge_weights(address,uint256)", _gauge, _amount));
    }

    function withdraw(
        address _gauge,
        address _token,
        uint256 _amount
    ) public returns (uint256) {
        require(strategies[msg.sender], "!strategy");
        //CurveYCRVVoter合约上token的金额
        uint256 _before = IERC20(_token).balanceOf(address(proxy));
        //执行Curve的的取款操作
        proxy.execute(_gauge, 0, abi.encodeWithSignature("withdraw(uint256)", _amount));
        //取款后token的余额
        uint256 _after = IERC20(_token).balanceOf(address(proxy));
        //差值
        uint256 _net = _after.sub(_before);
        //将token的差值转回策略合约，完成撤回投资操作
        proxy.execute(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _net));
        return _net;
    }

    //获取CurveYCRVVoter投资到Curve某个池子的总金额
    function balanceOf(address _gauge) public view returns (uint256) {
        return IERC20(_gauge).balanceOf(address(proxy));
    }

    //撤回某个token的全部投资
    function withdrawAll(address _gauge, address _token) external returns (uint256) {
        //限定：审核过的策略
        require(strategies[msg.sender], "!strategy");
        //调用withdraw
        return withdraw(_gauge, _token, balanceOf(_gauge));
    }

    //投资
    function deposit(address _gauge, address _token) external {
        //限定：审核过的策略
        require(strategies[msg.sender], "!strategy");
        //策略发送过来的投资额度
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        //转发给CurveYCRVVoter
        IERC20(_token).safeTransfer(address(proxy), _balance);
        //获取CurveYCRVVoter最后的额度
        _balance = IERC20(_token).balanceOf(address(proxy));
        //批准Curve可操作的token
        proxy.execute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _gauge, 0));
        proxy.execute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _gauge, _balance));
        //调用Curve的存款方法，完成投资
        (bool success, ) = proxy.execute(_gauge, 0, abi.encodeWithSignature("deposit(uint256)", _balance));
        if (!success) assert(false);
    }

    //收获Crv
    function harvest(address _gauge) external {
        //限定：审核过的策略
        require(strategies[msg.sender], "!strategy");
        //CurveYCRVVoter合约的crv
        uint256 _before = IERC20(crv).balanceOf(address(proxy));
        //挖crv，得到的crv仍然在CurveYCRVVoter合约中
        proxy.execute(mintr, 0, abi.encodeWithSignature("mint(address)", _gauge));
        //挖了后的crv
        uint256 _after = IERC20(crv).balanceOf(address(proxy));
        //本次挖得的crv
        uint256 _balance = _after.sub(_before);
        //crv发送回策略---策略继续crv的转换，进行复利投资
        proxy.execute(crv, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _balance));
    }
}
