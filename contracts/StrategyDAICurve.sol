/**
 *Submitted for verification at Etherscan.io on 2020-08-31
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

// DAI策略合约 地址:0xAa880345A3147a1fC6889080401C791813ed08Dc
contract StrategyDAICurve {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    // Dai Stablecoin (DAI)
    address public constant want = address(
        0x6B175474E89094C44Da98b954EedeAC495271d0F
    );
    // iearn DAI (yDAI)
    address public constant y = address(
        0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01
    );
    // Curve.fi yDAI/yUSDC/yUSDT/yTUSD (yDAI+yUSDC+yUSDT+yTUSD)
    address public constant ycrv = address(
        0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8
    );
    // yearn Curve.fi yDAI/yUSDC/yUSDT/yTUSD (yyDAI+yUSDC+yUSDT+yTUSD)
    address public constant yycrv = address(
        0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c
    );
    // Curve.fi: y Swap
    address public constant curve = address(
        0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51
    );
    // Dai Stablecoin (DAI)
    address public constant dai = address(
        0x6B175474E89094C44Da98b954EedeAC495271d0F
    );
    // iearn DAI (yDAI)
    address public constant ydai = address(
        0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01
    );
    // USD Coin (USDC)
    address public constant usdc = address(
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    );
    // iearn USDC (yUSDC)
    address public constant yusdc = address(
        0xd6aD7a6750A7593E092a9B218d66C0A814a3436e
    );
    // Tether USD (USDT)
    address public constant usdt = address(
        0xdAC17F958D2ee523a2206206994597C13D831ec7
    );
    // iearn USDT (yUSDT)
    address public constant yusdt = address(
        0x83f798e925BcD4017Eb265844FDDAbb448f1707D
    );
    // TrueUSD (TUSD)
    address public constant tusd = address(
        0x0000000000085d4780B73119b644AE5ecd22b376
    );
    // iearn TUSD (yTUSD)
    address public constant ytusd = address(
        0x73a052500105205d34Daf004eAb301916DA8190f
    );

    address public governance; // 0xfeb4acf3df3cdea7399794d0869ef76a6efaff52
    address public controller; // 0x9e65ad11b299ca0abefc2799ddb6314ef2d91080

    /**
     * @dev 构造函数
     * @param _controller 控制器合约地址
     */
    // 0x9e65ad11b299ca0abefc2799ddb6314ef2d91080
    constructor(address _controller) public {
        governance = msg.sender;
        controller = _controller;
    }
    /// @notice 获取合约名称
    function getName() external pure returns (string memory) {
        return "StrategyDAICurve";
    }

    /**
     * @dev 存款方法
     * @notice 
     */
    function deposit() public {
        // 当前合约在DAI合约中的余额
        uint256 _want = IERC20(want).balanceOf(address(this));
        // 如果DAI余额大于0
        if (_want > 0) {
            // 将DAI余额的数量批准给iearn DAI (yDAI)
            IERC20(want).safeApprove(y, 0);
            IERC20(want).safeApprove(y, _want);
            // 将DAI存款到yDAI合约
            yERC20(y).deposit(_want);
        }
        // 当前合约的yDAI余额
        uint256 _y = IERC20(y).balanceOf(address(this));
        // 如果yDAI余额>0
        if (_y > 0) {
            // 调用yDAI合约的批准方法批准给curve合约,数量为yDAI余额
            IERC20(y).safeApprove(curve, 0);
            IERC20(y).safeApprove(curve, _y);
            // 调用curve合约的添加流动性方法,将yDAI添加到curve合约
            ICurveFi(curve).add_liquidity([_y, 0, 0, 0], 0);
        }
        // 当前合约的yCrv余额
        uint256 _ycrv = IERC20(ycrv).balanceOf(address(this));
        // 如果yCrv余额>0
        if (_ycrv > 0) {
            // 调用yCrv合约的批准方法批准给yyCrv合约,数量为yCrv余额
            IERC20(ycrv).safeApprove(yycrv, 0);
            IERC20(ycrv).safeApprove(yycrv, _ycrv);
            // 调用yyCrv合约的存款,将yCrv存入到yyCrv合约
            yERC20(yycrv).deposit(_ycrv);
        }
    }

    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        require(y != address(_asset), "y");
        require(ycrv != address(_asset), "ycrv");
        require(yycrv != address(_asset), "yycrv");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint256 _amount) external {
        require(msg.sender == controller, "!controller");
        uint256 _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }

        address _vault = Controller(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
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

    function withdrawUnderlying(uint256 _amount) internal returns (uint256) {
        IERC20(ycrv).safeApprove(curve, 0);
        IERC20(ycrv).safeApprove(curve, _amount);
        ICurveFi(curve).remove_liquidity(_amount, [uint256(0), 0, 0, 0]);

        uint256 _yusdc = IERC20(yusdc).balanceOf(address(this));
        uint256 _yusdt = IERC20(yusdt).balanceOf(address(this));
        uint256 _ytusd = IERC20(ytusd).balanceOf(address(this));

        if (_yusdc > 0) {
            IERC20(yusdc).safeApprove(curve, 0);
            IERC20(yusdc).safeApprove(curve, _yusdc);
            ICurveFi(curve).exchange(1, 0, _yusdc, 0);
        }
        if (_yusdt > 0) {
            IERC20(yusdt).safeApprove(curve, 0);
            IERC20(yusdt).safeApprove(curve, _yusdt);
            ICurveFi(curve).exchange(2, 0, _yusdt, 0);
        }
        if (_ytusd > 0) {
            IERC20(ytusd).safeApprove(curve, 0);
            IERC20(ytusd).safeApprove(curve, _ytusd);
            ICurveFi(curve).exchange(3, 0, _ytusd, 0);
        }

        uint256 _before = IERC20(want).balanceOf(address(this));
        yERC20(ydai).withdraw(IERC20(ydai).balanceOf(address(this)));
        uint256 _after = IERC20(want).balanceOf(address(this));

        return _after.sub(_before);
    }

    function _withdrawAll() internal {
        uint256 _yycrv = IERC20(yycrv).balanceOf(address(this));
        if (_yycrv > 0) {
            yERC20(yycrv).withdraw(_yycrv);
            withdrawUnderlying(IERC20(ycrv).balanceOf(address(this)));
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
        return withdrawUnderlying(_after.sub(_before));
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
