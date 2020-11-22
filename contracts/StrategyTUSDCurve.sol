/**
 *Submitted for verification at Etherscan.io on 2020-08-29
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

interface yERC20 {
    function deposit(uint256) external;

    function withdraw(uint256) external;

    function getPricePerFullShare() external view returns (uint256);
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

// TUSD策略合约 地址:0x1d91E3F77271ed069618b4BA06d19821BC2ed8b0
contract StrategyTUSDCurve {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // TUSD
    address public constant want = address(
        0x0000000000085d4780B73119b644AE5ecd22b376
    );
    // yTUSD ilearn 机枪池
    address public constant y = address(
        0x73a052500105205d34Daf004eAb301916DA8190f
    );
    /**
     * ERC20 curve y池的lp token
     * name: Curve.fi yDAI/yUSDC/yUSDT/yTUSD
     * symbol: yDAI+yUSDC+yUSDT+yTUSD
     */
    address public constant ycrv = address(
        0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8
    );
    // yVault 保险库合约
    address public constant yycrv = address(
        0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c
    );
    // Curve y pool, 处理增加删除流动性或swap操作
    address public constant curve = address(
        0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51
    );

    // ERC20 DAI
    address public constant dai = address(
        0x6B175474E89094C44Da98b954EedeAC495271d0F
    );
    // yearn earn dai 机枪池
    address public constant ydai = address(
        0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01
    );

    address public constant usdc = address(
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    );
    address public constant yusdc = address(
        0xd6aD7a6750A7593E092a9B218d66C0A814a3436e
    );

    address public constant usdt = address(
        0xdAC17F958D2ee523a2206206994597C13D831ec7
    );
    address public constant yusdt = address(
        0x83f798e925BcD4017Eb265844FDDAbb448f1707D
    );

    address public constant tusd = address(
        0x0000000000085d4780B73119b644AE5ecd22b376
    );
    address public constant ytusd = address(
        0x73a052500105205d34Daf004eAb301916DA8190f
    );

    address public governance;
    address public controller;

    /**
     * @dev 构造函数
     * @param _controller 设置controller
     */
    constructor(address _controller) public {
        // 设置管理账号为创建合约的账号
        governance = msg.sender;
        // 设置Controller
        controller = _controller;
    }

    /**
     * 返回策略名
     */
    function getName() external pure returns (string memory) {
        return "StrategyTUSDCurve";
    }

    /**
     * @dev 存入 TUSD
     * @notice controller.earn方法中调用，调用前会前把TUSD转账过来
     */
    function deposit() public {
        // 查询TUSD在本合约的余额
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            IERC20(want).safeApprove(y, 0);
            IERC20(want).safeApprove(y, _want);
            // 存入yTUSD机枪池
            yERC20(y).deposit(_want);
        }
        // 把上一步得到的y lp token, 再投资到curve 的y池
        uint256 _y = IERC20(y).balanceOf(address(this));
        if (_y > 0) {
            IERC20(y).safeApprove(curve, 0);
            IERC20(y).safeApprove(curve, _y);
            // 存入ytusd
            ICurveFi(curve).add_liquidity([0, 0, 0, _y], 0);
        }
        // 把上一步得到的ycrv, 再投资到 yycrv(另一个保险库)中
        uint256 _ycrv = IERC20(ycrv).balanceOf(address(this));
        if (_ycrv > 0) {
            IERC20(ycrv).safeApprove(yycrv, 0);
            IERC20(ycrv).safeApprove(yycrv, _ycrv);
            yERC20(yycrv).deposit(_ycrv);
        }
    }

    /**
     * @dev 提取某资产
     * @notice 在万一的情况从Controller.inCaseStrategyTokenGetStuck调用提款
     */
    function withdraw(IERC20 _asset) external returns (uint256 balance) {
        // Controller only function for creating additional rewards from dust
        // 只有controller可以调用
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        require(y != address(_asset), "y");
        require(ycrv != address(_asset), "ycrv");
        require(yycrv != address(_asset), "yycrv");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }

    /**
     * @dev 正常的用户提款方法
     * @param _amount 提款数量
     */
    function withdraw(uint256 _amount) external {
        // Withdraw partial funds, normally used with a vault withdrawal
        require(msg.sender == controller, "!controller");
        uint256 _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            //  如果策略合约余额不足，就提款差额
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }

        address _vault = Controller(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        // 发给保险库
        IERC20(want).safeTransfer(_vault, _amount);
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        _withdrawAll();

        balance = IERC20(want).balanceOf(address(this));

        address _vault = Controller(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);
    }

    function withdrawTUSD(uint256 _amount) internal returns (uint256) {
        IERC20(ycrv).safeApprove(curve, 0);
        IERC20(ycrv).safeApprove(curve, _amount);
        // 取出y池的流动性
        ICurveFi(curve).remove_liquidity(_amount, [uint256(0), 0, 0, 0]);

        uint256 _ydai = IERC20(ydai).balanceOf(address(this));
        uint256 _yusdc = IERC20(yusdc).balanceOf(address(this));
        uint256 _yusdt = IERC20(yusdt).balanceOf(address(this));

        // 把其它token换成tusd
        if (_ydai > 0) {
            IERC20(ydai).safeApprove(curve, 0);
            IERC20(ydai).safeApprove(curve, _ydai);
            ICurveFi(curve).exchange(0, 3, _ydai, 0);
        }
        if (_yusdc > 0) {
            IERC20(yusdc).safeApprove(curve, 0);
            IERC20(yusdc).safeApprove(curve, _yusdc);
            ICurveFi(curve).exchange(1, 3, _yusdc, 0);
        }
        if (_yusdt > 0) {
            IERC20(yusdt).safeApprove(curve, 0);
            IERC20(yusdt).safeApprove(curve, _yusdt);
            ICurveFi(curve).exchange(2, 3, _yusdt, 0);
        }

        uint256 _before = IERC20(want).balanceOf(address(this));
        // 通过yToken在保险库中取出TUSD
        yERC20(ytusd).withdraw(IERC20(ytusd).balanceOf(address(this)));
        uint256 _after = IERC20(want).balanceOf(address(this));

        return _after.sub(_before);
    }

    function _withdrawAll() internal {
        uint256 _yycrv = IERC20(yycrv).balanceOf(address(this));
        if (_yycrv > 0) {
            yERC20(yycrv).withdraw(_yycrv);
            withdrawTUSD(IERC20(ycrv).balanceOf(address(this)));
        }
    }

    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        // calculate amount of ycrv to withdraw for amount of _want_
        uint256 _ycrv = _amount.mul(1e18).div(
            ICurveFi(curve).get_virtual_price()
        );
        // calculate amount of yycrv to withdraw for amount of _ycrv_
        uint256 _yycrv = _ycrv.mul(1e18).div(
            yERC20(yycrv).getPricePerFullShare()
        );
        uint256 _before = IERC20(ycrv).balanceOf(address(this));
        yERC20(yycrv).withdraw(_yycrv);
        uint256 _after = IERC20(ycrv).balanceOf(address(this));
        return withdrawTUSD(_after.sub(_before));
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfYYCRV() public view returns (uint256) {
        return IERC20(yycrv).balanceOf(address(this));
    }

    function balanceOfYYCRVinYCRV() public view returns (uint256) {
        return
            balanceOfYYCRV().mul(yERC20(yycrv).getPricePerFullShare()).div(
                1e18
            );
    }

    function balanceOfYYCRVinyTUSD() public view returns (uint256) {
        return
            balanceOfYYCRVinYCRV().mul(ICurveFi(curve).get_virtual_price()).div(
                1e18
            );
    }

    function balanceOfYCRV() public view returns (uint256) {
        return IERC20(ycrv).balanceOf(address(this));
    }

    function balanceOfYCRVyTUSD() public view returns (uint256) {
        return
            balanceOfYCRV().mul(ICurveFi(curve).get_virtual_price()).div(1e18);
    }

    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfYYCRVinyTUSD());
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
