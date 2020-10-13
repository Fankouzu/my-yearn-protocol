/**
 *Submitted for verification at Etherscan.io on 2020-02-12
 */

pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;
import "./common.sol";

// 0x83f798e925BcD4017Eb265844FDDAbb448f1707D
contract yUSDT is ERC20, ERC20Detailed, ReentrancyGuard, Structs, Ownable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 public pool; // 220854104054157
    address public token; // Tether: USDT Stablecoin
    address public compound; // Compound USD Coin (cUSDC)
    address public fulcrum; // Fulcrum USDC iToken (iUSDC) bZx USDC iToken
    address public aave; // Aave: Lending Pool Provider
    address public aaveToken; // Aave: aUSDT Token
    address public dydx; // dYdX: Solo Margin
    uint256 public dToken; // 0
    address public apr; // IEarnAPRWithPool

    enum Lender {NONE, DYDX, COMPOUND, AAVE, FULCRUM}

    Lender public provider = Lender.NONE;

    constructor() public ERC20Detailed("iearn USDT", "yUSDT", 6) {
        token = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
        apr = address(0xdD6d648C991f7d47454354f4Ef326b04025a48A8);
        dydx = address(0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e);
        aave = address(0x24a42fD28C976A61Df5D00D0599C34c4f90748c8);
        fulcrum = address(0xF013406A0B1d544238083DF0B93ad0d2cBE0f65f);
        aaveToken = address(0x71fc860F7D3A592A4a98740e39dB31d25db65ae8);
        compound = address(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
        dToken = 0;
        approveToken();
    }

    // Ownable setters incase of support in future for these systems
    function set_new_APR(address _new_APR) public onlyOwner {
        apr = _new_APR;
    }

    function set_new_FULCRUM(address _new_FULCRUM) public onlyOwner {
        fulcrum = _new_FULCRUM;
    }

    function set_new_COMPOUND(address _new_COMPOUND) public onlyOwner {
        compound = _new_COMPOUND;
    }

    function set_new_DTOKEN(uint256 _new_DTOKEN) public onlyOwner {
        dToken = _new_DTOKEN;
    }

    /**
     * @dev 存款方法
     * @param _amount 存款数额
     * @notice 当前合约在USDC的余额发送到当前合约,并铸造份额币
     */
    // 用于池交换的快速交换低gas方法
    // Quick swap low gas method for pool swaps
    function deposit(uint256 _amount) external nonReentrant {
        require(_amount > 0, "deposit must be greater than 0");
        // 池子数量 = 所有池子中的余额总和
        pool = _calcPoolValueInToken();
        // 将USDT发送到当前合约
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);

        // Calculate pool shares
        // 计算份额
        uint256 shares = 0;
        if (pool == 0) {
            shares = _amount;
            pool = _amount;
        } else {
            // 份额 = 存款数额 * 总量 / 池子数量
            shares = (_amount.mul(_totalSupply)).div(pool);
        }
        // 池子数量 = 所有池子中的余额总和
        pool = _calcPoolValueInToken();
        // 为调用者铸造份额
        _mint(msg.sender, shares);
    }

    /**
     * @dev 提款方法
     * @param _shares 份额数量
     * @notice
     */
    // 无需重新实施余额以降低费用并加快交换速度
    // No rebalance implementation for lower fees and faster swaps
    function withdraw(uint256 _shares) external nonReentrant {
        require(_shares > 0, "withdraw must be greater than 0");

        uint256 ibalance = balanceOf(msg.sender);
        require(_shares <= ibalance, "insufficient balance");

        // 池子数量 = 所有池子中的余额总和
        //可能来自cTokens的价值过高
        // Could have over value from cTokens
        pool = _calcPoolValueInToken();
        // 所有池子中的余额总和 * 份额 / 总量
        // Calc to redeem before updating balances
        uint256 r = (pool.mul(_shares)).div(_totalSupply);

        // 用户余额中减去份额
        _balances[msg.sender] = _balances[msg.sender].sub(
            _shares,
            "redeem amount exceeds balance"
        );
        // 总量中减去份额
        _totalSupply = _totalSupply.sub(_shares);

        emit Transfer(msg.sender, address(0), _shares);

        // 当前合约的USDT余额
        // Check balance
        uint256 b = IERC20(token).balanceOf(address(this));
        if (b < r) {
            // 赎回资产方法
            _withdrawSome(r.sub(b));
        }
        // 将USDT发送给用户
        IERC20(token).safeTransfer(msg.sender, r);
        // 更新池子总量
        pool = _calcPoolValueInToken();
    }

    function() external payable {}

    function recommend() public view returns (Lender) {
        (
            ,
            uint256 capr,
            uint256 iapr,
            uint256 aapr,
            uint256 dapr
        ) = IIEarnManager(apr).recommend(token);
        uint256 max = 0;
        if (capr > max) {
            max = capr;
        }
        if (iapr > max) {
            max = iapr;
        }
        if (aapr > max) {
            max = aapr;
        }
        if (dapr > max) {
            max = dapr;
        }

        Lender newProvider = Lender.NONE;
        if (max == capr) {
            newProvider = Lender.COMPOUND;
        } else if (max == iapr) {
            newProvider = Lender.FULCRUM;
        } else if (max == aapr) {
            newProvider = Lender.AAVE;
        } else if (max == dapr) {
            newProvider = Lender.DYDX;
        }
        return newProvider;
    }

    function supplyDydx(uint256 amount) public returns (uint256) {
        Info[] memory infos = new Info[](1);
        infos[0] = Info(address(this), 0);

        AssetAmount memory amt = AssetAmount(
            true,
            AssetDenomination.Wei,
            AssetReference.Delta,
            amount
        );
        ActionArgs memory act;
        act.actionType = ActionType.Deposit;
        act.accountId = 0;
        act.amount = amt;
        act.primaryMarketId = dToken;
        act.otherAddress = address(this);

        ActionArgs[] memory args = new ActionArgs[](1);
        args[0] = act;

        DyDx(dydx).operate(infos, args);
    }

    function _withdrawDydx(uint256 amount) internal {
        Info[] memory infos = new Info[](1);
        infos[0] = Info(address(this), 0);

        AssetAmount memory amt = AssetAmount(
            false,
            AssetDenomination.Wei,
            AssetReference.Delta,
            amount
        );
        ActionArgs memory act;
        act.actionType = ActionType.Withdraw;
        act.accountId = 0;
        act.amount = amt;
        act.primaryMarketId = dToken;
        act.otherAddress = address(this);

        ActionArgs[] memory args = new ActionArgs[](1);
        args[0] = act;

        DyDx(dydx).operate(infos, args);
    }

    function getAave() public view returns (address) {
        return LendingPoolAddressesProvider(aave).getLendingPool();
    }

    function getAaveCore() public view returns (address) {
        return LendingPoolAddressesProvider(aave).getLendingPoolCore();
    }

    function approveToken() public {
        IERC20(token).safeApprove(compound, uint256(-1)); //also add to constructor
        IERC20(token).safeApprove(dydx, uint256(-1));
        IERC20(token).safeApprove(getAaveCore(), uint256(-1));
        IERC20(token).safeApprove(fulcrum, uint256(-1));
    }

    function balance() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function balanceDydx() public view returns (uint256) {
        Wei memory bal = DyDx(dydx).getAccountWei(
            Info(address(this), 0),
            dToken
        );
        return bal.value;
    }

    /**
     * @dev cUSDC余额
     * @notice 当前合约在Compound USD Coin (cUSDC)的余额
     */
    function balanceCompound() public view returns (uint256) {
        return IERC20(compound).balanceOf(address(this));
    }

    function balanceCompoundInToken() public view returns (uint256) {
        // Mantisa 1e18 to decimals
        uint256 b = balanceCompound();
        if (b > 0) {
            b = b.mul(Compound(compound).exchangeRateStored()).div(1e18);
        }
        return b;
    }

    function balanceFulcrumInToken() public view returns (uint256) {
        uint256 b = balanceFulcrum();
        if (b > 0) {
            b = Fulcrum(fulcrum).assetBalanceOf(address(this));
        }
        return b;
    }

    function balanceFulcrum() public view returns (uint256) {
        return IERC20(fulcrum).balanceOf(address(this));
    }

    function balanceAave() public view returns (uint256) {
        return IERC20(aaveToken).balanceOf(address(this));
    }

    function _balance() internal view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @dev dydx获取特定帐户和市场的代币余额
     */
    function _balanceDydx() internal view returns (uint256) {
        // 获取特定帐户和市场的代币余额
        Wei memory bal = DyDx(dydx).getAccountWei(
            Info(address(this), 0),
            dToken
        );
        return bal.value;
    }

    /**
     * @dev cUSDC余额私有
     * @notice 当前合约在Compound USD Coin (cUSDC)的余额
     */
    function _balanceCompound() internal view returns (uint256) {
        return IERC20(compound).balanceOf(address(this));
    }

    /**
     * @notice 计算基础货币到CToken的汇率
     * @dev 此功能在计算汇率之前不产生利息
     * @return USDC余额
     */
    function _balanceCompoundInToken() internal view returns (uint256) {
        // Mantisa 1e18 to decimals
        // cUSDC余额
        uint256 b = balanceCompound();
        if (b > 0) {
            // cUSDC余额 * 计算基础货币到CToken的汇率 / 1e18
            b = b.mul(Compound(compound).exchangeRateStored()).div(1e18);
        }
        return b;
    }

    /**
     * @notice 返回bzx底层资产的余额
     * @return bZx USDC iToken的USDC余额
     */
    function _balanceFulcrumInToken() internal view returns (uint256) {
        uint256 b = balanceFulcrum();
        if (b > 0) {
            b = Fulcrum(fulcrum).assetBalanceOf(address(this));
        }
        return b;
    }

    function _balanceFulcrum() internal view returns (uint256) {
        return IERC20(fulcrum).balanceOf(address(this));
    }

    function _balanceAave() internal view returns (uint256) {
        return IERC20(aaveToken).balanceOf(address(this));
    }

    function _withdrawAll() internal {
        uint256 amount = _balanceCompound();
        if (amount > 0) {
            _withdrawCompound(amount);
        }
        amount = _balanceDydx();
        if (amount > 0) {
            _withdrawDydx(amount);
        }
        amount = _balanceFulcrum();
        if (amount > 0) {
            _withdrawFulcrum(amount);
        }
        amount = _balanceAave();
        if (amount > 0) {
            _withdrawAave(amount);
        }
    }

    function _withdrawSomeCompound(uint256 _amount) internal {
        uint256 b = balanceCompound();
        uint256 bT = balanceCompoundInToken();
        require(bT >= _amount, "insufficient funds");
        // can have unintentional rounding errors
        uint256 amount = (b.mul(_amount)).div(bT).add(1);
        _withdrawCompound(amount);
    }

    // 1999999614570950845
    function _withdrawSomeFulcrum(uint256 _amount) internal {
        // Balance of fulcrum tokens, 1 iDAI = 1.00x DAI
        uint256 b = balanceFulcrum(); // 1970469086655766652
        // Balance of token in fulcrum
        uint256 bT = balanceFulcrumInToken(); // 2000000803224344406
        require(bT >= _amount, "insufficient funds");
        // can have unintentional rounding errors
        uint256 amount = (b.mul(_amount)).div(bT).add(1);
        _withdrawFulcrum(amount);
    }

    function _withdrawSome(uint256 _amount) internal {
        if (provider == Lender.COMPOUND) {
            _withdrawSomeCompound(_amount);
        }
        if (provider == Lender.AAVE) {
            require(balanceAave() >= _amount, "insufficient funds");
            _withdrawAave(_amount);
        }
        if (provider == Lender.DYDX) {
            require(balanceDydx() >= _amount, "insufficient funds");
            _withdrawDydx(_amount);
        }
        if (provider == Lender.FULCRUM) {
            _withdrawSomeFulcrum(_amount);
        }
    }

    function rebalance() public {
        Lender newProvider = recommend();

        if (newProvider != provider) {
            _withdrawAll();
        }

        if (balance() > 0) {
            if (newProvider == Lender.DYDX) {
                supplyDydx(balance());
            } else if (newProvider == Lender.FULCRUM) {
                supplyFulcrum(balance());
            } else if (newProvider == Lender.COMPOUND) {
                supplyCompound(balance());
            } else if (newProvider == Lender.AAVE) {
                supplyAave(balance());
            }
        }

        provider = newProvider;
    }

    // Internal only rebalance for better gas in redeem
    function _rebalance(Lender newProvider) internal {
        if (_balance() > 0) {
            if (newProvider == Lender.DYDX) {
                supplyDydx(_balance());
            } else if (newProvider == Lender.FULCRUM) {
                supplyFulcrum(_balance());
            } else if (newProvider == Lender.COMPOUND) {
                supplyCompound(_balance());
            } else if (newProvider == Lender.AAVE) {
                supplyAave(_balance());
            }
        }
        provider = newProvider;
    }

    function supplyAave(uint256 amount) public {
        Aave(getAave()).deposit(token, amount, 0);
    }

    function supplyFulcrum(uint256 amount) public {
        require(
            Fulcrum(fulcrum).mint(address(this), amount) > 0,
            "FULCRUM: supply failed"
        );
    }

    function supplyCompound(uint256 amount) public {
        require(
            Compound(compound).mint(amount) == 0,
            "COMPOUND: supply failed"
        );
    }

    function _withdrawAave(uint256 amount) internal {
        AToken(aaveToken).redeem(amount);
    }

    function _withdrawFulcrum(uint256 amount) internal {
        require(
            Fulcrum(fulcrum).burn(address(this), amount) > 0,
            "FULCRUM: withdraw failed"
        );
    }

    function _withdrawCompound(uint256 amount) internal {
        require(
            Compound(compound).redeem(amount) == 0,
            "COMPOUND: withdraw failed"
        );
    }

    function _calcPoolValueInToken() internal view returns (uint256) {
        // Compound USDC余额 + bzx USDC余额 +
        return
            _balanceCompoundInToken()
                .add(_balanceFulcrumInToken())
                .add(_balanceDydx())
                .add(_balanceAave())
                .add(_balance());
    }

    function calcPoolValueInToken() public view returns (uint256) {
        return
            balanceCompoundInToken()
                .add(balanceFulcrumInToken())
                .add(balanceDydx())
                .add(balanceAave())
                .add(balance());
    }

    function getPricePerFullShare() public view returns (uint256) {
        uint256 _pool = calcPoolValueInToken();
        return _pool.mul(1e18).div(_totalSupply);
    }
}
