/**
 *Submitted for verification at Etherscan.io on 2020-09-22
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

// curve.fi/y LP策略合约 地址:0x594a198048501A304267E63B3bAd0f0638da7628
contract StrategyCurveYVoterProxy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // Curve.fi yDAI/yUSDC/yUSDT/yTUSD (yDAI+yUSDC+yUSDT+yTUSD)
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

    uint256 public keepCRV = 1000;
    uint256 public constant keepCRVMax = 10000;

    uint256 public performanceFee = 500;
    uint256 public constant performanceMax = 10000;

    uint256 public withdrawalFee = 50;
    uint256 public constant withdrawalMax = 10000;

    address public governance;
    address public controller;
    address public strategist;

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

    function setKeepCRV(uint256 _keepCRV) external {
        require(msg.sender == governance, "!governance");
        keepCRV = _keepCRV;
    }

    /**
     * @dev 设置提款手续费
     * @param _withdrawalFee 提款手续费
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
     * @notice 
     */
    function deposit() public {
        // 当前合约在yCrv合约中的余额
        uint256 _want = IERC20(want).balanceOf(address(this));
        // 如果余额大于0
        if (_want > 0) {
            // 将yCrv余额批准给yEarn StrategyProxy
            IERC20(want).safeTransfer(proxy, _want);
            // 
            VoterProxy(proxy).deposit(gauge, want);
        }
    }

    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        require(crv != address(_asset), "crv");
        require(ydai != address(_asset), "ydai");
        require(dai != address(_asset), "dai");
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

        uint256 _fee = _amount.mul(withdrawalFee).div(withdrawalMax);

        IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
        address _vault = Controller(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds

        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
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

    function _withdrawAll() internal {
        VoterProxy(proxy).withdrawAll(gauge, want);
    }

    function harvest() public {
        require(
            msg.sender == strategist || msg.sender == governance,
            "!authorized"
        );
        VoterProxy(proxy).harvest(gauge);
        uint256 _crv = IERC20(crv).balanceOf(address(this));
        if (_crv > 0) {
            uint256 _keepCRV = _crv.mul(keepCRV).div(keepCRVMax);
            IERC20(crv).safeTransfer(voter, _keepCRV);
            _crv = _crv.sub(_keepCRV);

            IERC20(crv).safeApprove(uni, 0);
            IERC20(crv).safeApprove(uni, _crv);

            address[] memory path = new address[](3);
            path[0] = crv;
            path[1] = weth;
            path[2] = dai;

            Uni(uni).swapExactTokensForTokens(
                _crv,
                uint256(0),
                path,
                address(this),
                now.add(1800)
            );
        }
        uint256 _dai = IERC20(dai).balanceOf(address(this));
        if (_dai > 0) {
            IERC20(dai).safeApprove(ydai, 0);
            IERC20(dai).safeApprove(ydai, _dai);
            yERC20(ydai).deposit(_dai);
        }
        uint256 _ydai = IERC20(ydai).balanceOf(address(this));
        if (_ydai > 0) {
            IERC20(ydai).safeApprove(curve, 0);
            IERC20(ydai).safeApprove(curve, _ydai);
            ICurveFi(curve).add_liquidity([_ydai, 0, 0, 0], 0);
        }
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            uint256 _fee = _want.mul(performanceFee).div(performanceMax);
            IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
            deposit();
        }
    }

    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        return VoterProxy(proxy).withdraw(gauge, want, _amount);
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfPool() public view returns (uint256) {
        return VoterProxy(proxy).balanceOf(gauge);
    }

    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
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
