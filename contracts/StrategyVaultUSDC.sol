/**
 *Submitted for verification at Etherscan.io on 2020-08-13
*/

/**
 *Submitted for verification at Etherscan.io on 2020-08-04
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.5.17;

import "./common.sol";

interface Vault {
    function deposit(uint) external;
    function withdraw(uint) external;
    function getPricePerFullShare() external view returns (uint);
}

interface Aave {
    function borrow(address _reserve, uint _amount, uint _interestRateModel, uint16 _referralCode) external;
    function setUserUseReserveAsCollateral(address _reserve, bool _useAsCollateral) external;
    function repay(address _reserve, uint _amount, address payable _onBehalfOf) external payable;
    function getUserAccountData(address _user)
        external
        view
        returns (
            uint totalLiquidityETH,
            uint totalCollateralETH,
            uint totalBorrowsETH,
            uint totalFeesETH,
            uint availableBorrowsETH,
            uint currentLiquidationThreshold,
            uint ltv,
            uint healthFactor
        );
    function getUserReserveData(address _reserve, address _user)
        external
        view
        returns (
            uint currentATokenBalance,
            uint currentBorrowBalance,
            uint principalBorrowBalance,
            uint borrowRateMode,
            uint borrowRate,
            uint liquidityRate,
            uint originationFee,
            uint variableBorrowIndex,
            uint lastUpdateTimestamp,
            bool usageAsCollateralEnabled
        );
}

interface LendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);
    function getLendingPoolCore() external view returns (address);
    function getPriceOracle() external view returns (address);
}

/*

 策略必须执行以下调用；

 - deposit() 存款
 - withdraw(address) 必须排除yield中使用的所有令牌-Controller角色-withdraw应该返回给Controller
 - withdraw(uint) - 控制器 | 保管箱角色-提款应始终返回保管库
 - withdrawAll() - 控制器 | 保管箱角色-提款应始终返回保管库
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

// aLINK策略合约 地址:0x25fAcA21dd2Ad7eDB3a027d543e617496820d8d6
contract StrategyVaultUSDC {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    //USDC 合约地址
    address constant public want = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    //yUSDC 保险库合约地址
    address constant public vault = address(0x597aD1e0c13Bfe8025993D9e79C69E1c0233522e);
    //Aave: Lending Pool Provider 地址
    address public constant aave = address(0x24a42fD28C976A61Df5D00D0599C34c4f90748c8);

    address public governance;//治理地址----主要用于治理权限检验
    address public controller;//控制器地址-----主要用于与本合约的资金交互
    
    /**
     * @dev 构造函数
     * @param _controller 控制器合约地址
     */
    constructor(address _controller) public {
        governance = msg.sender;
        controller = _controller;
    }
    
    function deposit() external {
        // USDC余额 = 当前合约在USDC合约中的余额
        uint _balance = IERC20(want).balanceOf(address(this));
        if (_balance > 0) {
            // 将USDC的余额批准给yUSDC
            IERC20(want).safeApprove(address(vault), 0);
            IERC20(want).safeApprove(address(vault), _balance);
            //将余额充值进yUSDC保险库
            Vault(vault).deposit(_balance);
        }
    }
    //获取aave贷款池的地址
    function getAave() public view returns (address) {
        return LendingPoolAddressesProvider(aave).getLendingPool();
    }
    //获取当前策略合约的名称
    function getName() external pure returns (string memory) {
        return "StrategyVaultUSDC";
    }
    //获取保险库在aave的借出资产计息余额
    function debt() external view returns (uint) {
        (,uint currentBorrowBalance,,,,,,,,) = Aave(getAave()).getUserReserveData(want, Controller(controller).vaults(address(this)));
        return currentBorrowBalance;
    }
    
    function have() public view returns (uint) {
        uint _have = balanceOf();
        return _have;
    }
    
    function skimmable() public view returns (uint) {
        (,uint currentBorrowBalance,,,,,,,,) = Aave(getAave()).getUserReserveData(want, Controller(controller).vaults(address(this)));
        uint _have = have();
        if (_have > currentBorrowBalance) {
            return _have.sub(currentBorrowBalance);
        } else {
            return 0;
        }
    }

    function skim() external {
        uint _balance = IERC20(want).balanceOf(address(this));
        uint _amount = skimmable();
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        } 
        IERC20(want).safeTransfer(controller, _amount);
    }
    
    //提供给控制器，用于创建额外奖励的方法
    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        //执行者必须是控制管理员
        require(msg.sender == controller, "!controller");
        //不能是want地址
        require(address(_asset) != address(want), "!want");
        //不能是保险库地址
        require(address(_asset) != address(vault), "!vault");
        //获取余额并转账给控制器
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }
    //提取部分资金，通常用于保险库提取
    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint _amount) external {
        //执行者必须是控制管理员
        require(msg.sender == controller, "!controller");
        //当前合约在USDC 合约中余额
        uint _balance = IERC20(want).balanceOf(address(this));
        //如果USDC中余额不够提取数额，则从保险库提取差额部分
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }
        address _vault = Controller(controller).vaults(address(this));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, _amount);
    }
    //全部提取，通常用于迁移合约
    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint balance) {
        //执行者必须是控制管理员
        require(msg.sender == controller, "!controller");

        //全部提取，调用保险库提取方法
        _withdrawAll();

        //当前合约在USDC 合约中余额
        balance = IERC20(want).balanceOf(address(this));
        //从控制器获取当前合约地址对应的保险库地址
        address _vault = Controller(controller).vaults(address(this));
        //判断是否零地址，防止被销毁
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        //将USDC中余额转入保险库
        IERC20(want).safeTransfer(_vault, balance);
    }
    //保险库全部提取，调用保险库提取方法
    function _withdrawAll() internal {
        Vault(vault).withdraw(IERC20(vault).balanceOf(address(this)));
    }
    
    /**
     * @dev 保险库中部分提取
     * @param _amount  提取数额
     */
    function _withdrawSome(uint256 _amount) internal returns (uint) {
        //计算提取的份额数量
        uint _redeem = IERC20(vault).balanceOf(address(this)).mul(_amount).div(balanceSavingsInToken());
        //获取提取前USDC中当前合约地址的余额
        uint _before = IERC20(want).balanceOf(address(this));
        //调用保险库合约方法完成部分提取
        Vault(vault).withdraw(_redeem);
        //获取提取后USDC中当前合约地址的余额
        uint _after = IERC20(want).balanceOf(address(this));
        //返回USDC的变动数量
        return _after.sub(_before);
    }
    //当前余额 =  当前合约在USDC合约中的余额 + 当前合约在yUSDC保险库的USDC余额
    function balanceOf() public view returns (uint) {
        return IERC20(want).balanceOf(address(this))
                .add(balanceSavingsInToken());
    }
    // 当前合约在yUSDC保险库的USDC余额 = 当前策略合约地址在yUSDC保险库合约中的余额 * 保险库中每份基础资产对应的份额 /  1e18
    function balanceSavingsInToken() public view returns (uint256) {
        return IERC20(vault).balanceOf(address(this)).mul(Vault(vault).getPricePerFullShare()).div(1e18);
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