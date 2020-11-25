// SPDX-License-Identifier: MIT

pragma solidity ^0.5.17;

import "@openzeppelinV2/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV2/contracts/math/SafeMath.sol";
import "@openzeppelinV2/contracts/utils/Address.sol";
import "@openzeppelinV2/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/curve/Curve.sol";
import "../../interfaces/curve/Gauge.sol";
import "../../interfaces/curve/Mintr.sol";
import "../../interfaces/curve/VoteEscrow.sol";
import "../../interfaces/uniswap/Uni.sol";
import "../../interfaces/yearn/IToken.sol";

/**
* Y池投资代理
* Lucas
*/
contract CurveYCRVVoter {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    //yDAI+yUSDC+yUSDT+yTUSD 
    address public constant want = address(0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8);
    //Curve的pool yDAI/yUSDC/yUSDT/yTUSD 
    address public constant pool = address(0xFA712EE4788C042e2B7BB55E6cb8ec569C4530c1);
    //Curve Token Minter 用于Crv的分发挖矿
    address public constant mintr = address(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0);
    //crv token
    address public constant crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    /*
    @notice Votes have a weight depending on time, so that users are
            committed to the future of (whatever they are voting for)
    @dev Vote weight decays linearly over time. Lock time cannot be
        more than `MAXTIME` (4 years).
    """

    # Voting escrow to have time-weighted votes
    # Votes have a weight depending on time, so that users are committed
    # to the future of (whatever they are voting for).
    # The weight in this implementation is linear, and lock cannot be more than maxtime:
    # w ^
    # 1 +        /
    #   |      /
    #   |    /
    #   |  /
    #   |/
    # 0 +--------+------> time
    #       maxtime (4 years?)
    */
    address public constant escrow = address(0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2);

    address public governance;
    address public strategy;

    constructor() public {
        governance = msg.sender;
    }

    //获取名字
    function getName() external pure returns (string memory) {
        return "CurveYCRVVoter";
    }

    //设置策略
    function setStrategy(address _strategy) external {
        require(msg.sender == governance, "!governance");
        strategy = _strategy;
    }

    //y池的投资方法
    function deposit() public {
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            IERC20(want).safeApprove(pool, 0);
            IERC20(want).safeApprove(pool, _want);
            Gauge(pool).deposit(_want);
        }
    }

    //额外币种取回控制器
    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint256 balance) {
        require(msg.sender == strategy, "!controller");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(strategy, balance);
    }

    //yDAI+yUSDC+yUSDT+yTUSD 取回到策略
    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint256 _amount) external {
        require(msg.sender == strategy, "!controller");
        uint256 _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }
        IERC20(want).safeTransfer(strategy, _amount);
    }

    //yDAI+yUSDC+yUSDT+yTUSD  全部取回到策略
    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint256 balance) {
        require(msg.sender == strategy, "!controller");
        _withdrawAll();

        balance = IERC20(want).balanceOf(address(this));
        IERC20(want).safeTransfer(strategy, balance);
    }

    //从Curve yDAI+yUSDC+yUSDT+yTUSD  Pool中全部撤回到本合约
    function _withdrawAll() internal {
        Gauge(pool).withdraw(Gauge(pool).balanceOf(address(this)));
    }

    //托管合约，锁定crv
    function createLock(uint256 _value, uint256 _unlockTime) external {
        require(msg.sender == strategy || msg.sender == governance, "!authorized");
        IERC20(crv).safeApprove(escrow, 0);
        IERC20(crv).safeApprove(escrow, _value);
        VoteEscrow(escrow).create_lock(_value, _unlockTime);
    }

    //托管合约，增加crv
    function increaseAmount(uint256 _value) external {
        require(msg.sender == strategy || msg.sender == governance, "!authorized");
        IERC20(crv).safeApprove(escrow, 0);
        IERC20(crv).safeApprove(escrow, _value);
        VoteEscrow(escrow).increase_amount(_value);
    }

    //从托管合约取回crv到本合约
    function release() external {
        require(msg.sender == strategy || msg.sender == governance, "!authorized");
        VoteEscrow(escrow).withdraw();
    }

    //从Curve中部分取款
    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        Gauge(pool).withdraw(_amount);
        return _amount;
    }

    //未投资余额
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    //已投资余额
    function balanceOfPool() public view returns (uint256) {
        return Gauge(pool).balanceOf(address(this));
    }

    //获取总余额
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    //设置治理地址
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    //操作代理，实现了：允许StrategyProxy和治理地址操作本合约的金额
    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool, bytes memory) {
        require(msg.sender == strategy || msg.sender == governance, "!governance");
        (bool success, bytes memory result) = to.call.value(value)(data);

        return (success, result);
    }
}
