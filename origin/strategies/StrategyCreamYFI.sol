// SPDX-License-Identifier: MIT

pragma solidity ^0.5.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/cream/Controller.sol";
import "../../interfaces/compound/Token.sol";
import "../../interfaces/uniswap/Uni.sol";

import "../../interfaces/yearn/IController.sol";

contract StrategyCreamYFI {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    // YFI Token
    address public constant want = address(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e);
    // Unitroller
    Creamtroller public constant creamtroller = Creamtroller(0x3d5BC3c8d13dcB8bF317092d84783c2697AE9258);
    // Cream.Finance: crYFI Token
    address public constant crYFI = address(0xCbaE0A83f4f9926997c8339545fb8eE32eDc6b76);
    // Cream.Finance: CREAM Token
    address public constant cream = address(0x2ba592F78dB6436527729929AAf6c908497cB200);
    // Uniswap V2: Router 2
    address public constant uni = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    // Wrapped Ether
    address public constant weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // used for cream <> weth <> yfi route

    uint256 public performanceFee = 500;
    uint256 public constant performanceMax = 10000;

    uint256 public withdrawalFee = 50;
    uint256 public constant withdrawalMax = 10000;

    address public governance;
    address public controller;
    address public strategist;

    constructor(address _controller) public {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
    }

    function getName() external pure returns (string memory) {
        return "StrategyCreamYFI";
    }

    function setStrategist(address _strategist) external {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }

    function setWithdrawalFee(uint256 _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        withdrawalFee = _withdrawalFee;
    }

    function setPerformanceFee(uint256 _performanceFee) external {
        require(msg.sender == governance, "!governance");
        performanceFee = _performanceFee;
    }

    /**
     * @dev 存款方法
     * @notice 从want地址获取当前合约的余额,
     * 如果余额大于0,从crYFI批准_want数量,crYFI铸造_want数额给当前合约
     * 相当于将当前合约在want合约的余额铸造到crYFI合约
     */
    function deposit() public {
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            IERC20(want).safeApprove(crYFI, 0);
            IERC20(want).safeApprove(crYFI, _want);
            cToken(crYFI).mint(_want);
        }
    }

    /**
     * @dev 提款方法
     * @param _asset 资产地址
     * @notice 将当前合约在_asset资产合约的余额发送给控制器合约
     */
    // 控制器仅用于从灰尘中产生额外奖励的功能
    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        require(crYFI != address(_asset), "crYFI");
        require(cream != address(_asset), "cream");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }

    /**
     * @dev 提款方法
     * @param _amount 提款数额
     * @notice 必须从控制器合约调用
     */
    // 提取部分资金，通常用于金库提取
    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint256 _amount) external {
        require(msg.sender == controller, "!controller");
        uint256 _balance = IERC20(want).balanceOf(address(this));
        // 如果当前合约在want合约的余额小于给定的_amount
        if (_balance < _amount) {
            // 数额 = 赎回资产(数额 - 余额)
            _amount = _withdrawSome(_amount.sub(_balance));
            // 数额 + 余额
            _amount = _amount.add(_balance);
        }
        // 费用 = 数额 * 提款费 / 提款最大值
        uint256 _fee = _amount.mul(withdrawalFee).div(withdrawalMax);

        // 将费用发送到控制器奖励地址
        IERC20(want).safeTransfer(IController(controller).rewards(), _fee);
        // 保险库 = want合约在控制器的保险库地址
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        // 将数额 - 费用 发送到保险库地址
        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
    }

    /**
     * @dev 提款全部方法
     * @notice 必须从控制器合约调用
     */
    // 提取所有资金，通常在迁移策略时使用
    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        // 从Ctoken赎回资产
        _withdrawAll();
        // 当前合约在want合约中的余额
        balance = IERC20(want).balanceOf(address(this));

        // 保险库地址
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        // 所有余额发送到保险库
        IERC20(want).safeTransfer(_vault, balance);
    }

    /**
     * @dev 内部提款全部方法
     * @notice 如果CToken的余额大于0,从Ctoken赎回资产(b * crYFI的汇率存储 / 1e18 - 1)
     */
    function _withdrawAll() internal {
        uint256 amount = balanceC();
        if (amount > 0) {
            _withdrawSome(balanceCInToken().sub(1));
        }
    }

    /**
     * @dev 收获方法
     * @notice 
     */
    function harvest() public {
        // 只能从策略账户或治理账户调用
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        // 声明所有市场中持有人应得的所有补偿金
        Creamtroller(creamtroller).claimComp(address(this));
        // 当前合约在cream合约的余额
        uint256 _cream = IERC20(cream).balanceOf(address(this));
        if (_cream > 0) {
            // 将当前合约_cream数量的cream批准给uniswap路由合约
            IERC20(cream).safeApprove(uni, 0);
            IERC20(cream).safeApprove(uni, _cream);
            // 交易路径cream=>weth=>want
            address[] memory path = new address[](3);
            path[0] = cream;
            path[1] = weth;
            path[2] = want;
            // 调用uniswap用精确的token交换尽量多的token方法,用cream换want,发送到当前合约
            Uni(uni).swapExactTokensForTokens(_cream, uint256(0), path, address(this), now.add(1800));
        }
        // 当前合约的want余额
        uint256 _want = IERC20(want).balanceOf(address(this));
        // 如果want余额大于0
        if (_want > 0) {
            // 手续费 = want * 费率 / 费率最大值
            uint256 _fee = _want.mul(performanceFee).div(performanceMax);
            // 将手续费发送到奖励地址
            IERC20(want).safeTransfer(IController(controller).rewards(), _fee);
            // 存款方法
            deposit();
        }
    }

    /**
     * @dev 赎回资产方法
     * @param _amount 数额
     * @notice 根据当前合约在CToken的余额计算出可以在CToken中赎回的数额,并赎回资产
     */
    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        // 当前合约在crYFI的余额
        uint256 b = balanceC();
        // b * crYFI的汇率存储 / 1e18
        uint256 bT = balanceCInToken();
        // 可能会有意外的舍入错误
        // can have unintentional rounding errors
        // 数额 = (b * _amount) / bT + 1
        uint256 amount = (b.mul(_amount)).div(bT).add(1);
        // 之前 = 当前合约在want合约中的余额
        uint256 _before = IERC20(want).balanceOf(address(this));
        // 当前合约赎回cToken，以换取基础资产
        _withdrawC(amount);
        // 之后 = 当前合约在want合约中的余额
        uint256 _after = IERC20(want).balanceOf(address(this));
        // 提款数额 = 之后 - 之前
        uint256 _withdrew = _after.sub(_before);
        // 返回提款数额
        return _withdrew;
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function _withdrawC(uint256 amount) internal {
        // 当前合约赎回cToken，以换取基础资产
        cToken(crYFI).redeem(amount);
    }

    function balanceCInToken() public view returns (uint256) {
        // Mantisa 1e18 to decimals
        uint256 b = balanceC();
        if (b > 0) {
            // 计算基础货币到CToken的汇率
            b = b.mul(cToken(crYFI).exchangeRateStored()).div(1e18);
        }
        return b;
    }

    function balanceC() public view returns (uint256) {
        return IERC20(crYFI).balanceOf(address(this));
    }

    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceCInToken());
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
