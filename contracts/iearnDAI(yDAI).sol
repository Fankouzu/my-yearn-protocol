/**
 *Submitted for verification at Etherscan.io on 2020-02-12
 */

pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

interface Compound {
    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function exchangeRateStored() external view returns (uint256);
}

interface Fulcrum {
    function mint(address receiver, uint256 amount)
        external
        payable
        returns (uint256 mintAmount);

    function burn(address receiver, uint256 burnAmount)
        external
        returns (uint256 loanAmountPaid);

    function assetBalanceOf(address _owner)
        external
        view
        returns (uint256 balance);
}

interface ILendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);
}

interface Aave {
    function deposit(
        address _reserve,
        uint256 _amount,
        uint16 _referralCode
    ) external;
}

interface AToken {
    function redeem(uint256 amount) external;
}

interface IIEarnManager {
    function recommend(address _token)
        external
        view
        returns (
            string memory choice,
            uint256 capr,
            uint256 iapr,
            uint256 aapr,
            uint256 dapr
        );
}

contract Structs {
    struct Val {
        uint256 value;
    }

    enum ActionType {
        Deposit, // supply tokens
        Withdraw // borrow tokens
    }

    enum AssetDenomination {
        Wei // the amount is denominated in wei
    }

    enum AssetReference {
        Delta // the amount is given as a delta from the current value
    }

    struct AssetAmount {
        bool sign; // true if positive
        AssetDenomination denomination;
        AssetReference ref;
        uint256 value;
    }

    struct ActionArgs {
        ActionType actionType;
        uint256 accountId;
        AssetAmount amount;
        uint256 primaryMarketId;
        uint256 secondaryMarketId;
        address otherAddress;
        uint256 otherAccountId;
        bytes data;
    }

    struct Info {
        address owner; // The address that owns the account
        uint256 number; // A nonce that allows a single address to control many accounts
    }

    struct Wei {
        bool sign; // true if positive
        uint256 value;
    }
}

contract DyDx is Structs {
    function getAccountWei(Info memory account, uint256 marketId)
        public
        view
        returns (Wei memory);

    function operate(Info[] memory, ActionArgs[] memory) public;
}

interface LendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);

    function getLendingPoolCore() external view returns (address);
}

// iearn DAI (yDAI)合约 地址:0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01
contract yDAI is ERC20, ERC20Detailed, ReentrancyGuard, Structs {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 public pool;
    address public token;
    address public compound;
    address public fulcrum;
    address public aave;
    address public aaveToken;
    address public dydx;
    uint256 public dToken;
    address public apr;

    enum Lender {NONE, DYDX, COMPOUND, AAVE, FULCRUM}

    Lender public provider = Lender.NONE;

    function() external payable {}

    constructor() public ERC20Detailed("iearn DAI", "yDAI", 18) {
        // Dai Stablecoin (DAI)
        token = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        apr = address(0xdD6d648C991f7d47454354f4Ef326b04025a48A8);
        dydx = address(0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e);
        aave = address(0x24a42fD28C976A61Df5D00D0599C34c4f90748c8);
        // Fulcrum DAI iToken (iDAI) bZx DAI iToken
        fulcrum = address(0x493C57C4763932315A328269E1ADaD09653B9081);
        aaveToken = address(0xfC1E690f61EFd961294b3e1Ce3313fBD8aa4f85d);
        compound = address(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        // dydx中的marketId
        dToken = 3;
        approveToken();
    }

    /**
     * @dev 批准全部
     * @notice 调用DAI合约的approve方法批准4个项目最大数额
     */
    function approveToken() public {
        IERC20(token).safeApprove(compound, uint256(-1)); //also add to constructor
        IERC20(token).safeApprove(dydx, uint256(-1));
        IERC20(token).safeApprove(getAaveCore(), uint256(-1));
        IERC20(token).safeApprove(fulcrum, uint256(-1));
    }

    /**
     * @dev 获取Aave项目借款池核心合约地址
     */
    function getAaveCore() public view returns (address) {
        return LendingPoolAddressesProvider(aave).getLendingPoolCore();
    }

    ///////////////////////////////////存款////////////////////////////////

    /**
     * @dev 存款方法
     * @param _amount 存入的DAI数额
     * @notice 将存入的DAI放到当前合约中,根据当前合约在所有其他项目中的DAI余额计算份额,为用户铸造份额
     */
    // 用于池交换的快速交换低耗气方法
    // Quick swap low gas method for pool swaps
    function deposit(uint256 _amount) external nonReentrant {
        // 确认_amount数额大于0
        require(_amount > 0, "deposit must be greater than 0");
        // 池子总量 = 当前合约在(Compound合约,bZx合约,dydx合约,Aave合约,DAI合约)中的DAI余额
        pool = _calcPoolValueInToken();

        // 从调用者账户向当前合约发送数量为_amount的DAI
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);

        // 计算池子份额
        // Calculate pool shares
        uint256 shares = 0;
        // 如果池子总量 == 0
        if (pool == 0) {
            // 份额 = _amount
            shares = _amount;
            // 池子总量 = _amount
            pool = _amount;
        } else {
            // 份额 = _amount * 当前合约的totalSupply / 池子总量
            shares = (_amount.mul(_totalSupply)).div(pool);
        }
        // 池子总量 = 当前合约在(Compound合约,bZx合约,dydx合约,Aave合约,DAI合约)中的DAI余额
        pool = _calcPoolValueInToken();
        // 为调用者铸造份额
        _mint(msg.sender, shares);
    }

    /**
     * @dev 投资方法
     * @param _amount 数额
     */
    function invest(uint256 _amount) external nonReentrant {
        require(_amount > 0, "deposit must be greater than 0");
        // 池子数额 = 计算资产总和
        pool = calcPoolValueInToken();

        // 从调用者向当前合约发送数额为_amount的DAI
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);

        // 调用移仓方法
        rebalance();

        // 计算池子份额
        // Calculate pool shares
        uint256 shares = 0;
        // 如果池子总量 == 0
        if (pool == 0) {
            // 份额 = _amount
            shares = _amount;
            // 池子总量 = _amount
            pool = _amount;
        } else {
            // 份额 = _amount * 当前合约的totalSupply / 池子总量
            shares = (_amount.mul(_totalSupply)).div(pool);
        }
        // 池子总量 = 当前合约在(Compound合约,bZx合约,dydx合约,Aave合约,DAI合约)中的DAI余额
        pool = calcPoolValueInToken();
        // 为调用者铸造份额
        _mint(msg.sender, shares);
    }

    /**
     * @dev 存款到Aave项目的方法
     * @param amount 存入的DAI数量
     * @notice 调用Aave合约的存款方法存入amount数量的DAI
     */
    function supplyAave(uint256 amount) public {
        Aave(getAave()).deposit(token, amount, 0);
    }

    /**
     * @dev 获取当前Aave项目借款池的方法
     */
    function getAave() public view returns (address) {
        return LendingPoolAddressesProvider(aave).getLendingPool();
    }

    /**
     * @dev 存款到bZx项目的方法
     * @param amount 存入的DAI数量
     * @notice 调用bZx合约的铸造方法存入amount数量的DAI
     */
    function supplyFulcrum(uint256 amount) public {
        require(
            Fulcrum(fulcrum).mint(address(this), amount) > 0,
            "FULCRUM: supply failed"
        );
    }

    /**
     * @dev 存款到Compound项目的方法
     * @param amount 存入的DAI数量
     * @notice 调用Compound合约的铸造方法存入amount数量的DAI
     */
    function supplyCompound(uint256 amount) public {
        require(
            Compound(compound).mint(amount) == 0,
            "COMPOUND: supply failed"
        );
    }

    /**
     * @dev 向dydx项目中存入资产
     * @param _amount 赎回的DAI数额
     */
    function supplyDydx(uint256 amount) public returns (uint256) {
        // 当前合约在dydx项目中的余额
        Info[] memory infos = new Info[](1);
        infos[0] = Info(address(this), 0);

        // 制作存入资产需要的参数
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

        // 存入DAI资产
        DyDx(dydx).operate(infos, args);
    }

    ///////////////////////////////////取款////////////////////////////////

    /**
     * @dev 取款方法
     * @param _shares 取出的份额
     * @notice 将存入的DAI放到当前合约中,根据当前合约在所有其他项目中的DAI余额计算份额,为用户铸造份额
     */
    // 无需重新实施余额以降低费用并加快交换速度
    // No rebalance implementation for lower fees and faster swaps
    function withdraw(uint256 _shares) external nonReentrant {
        // 确认取出份额>0
        require(_shares > 0, "withdraw must be greater than 0");

        // 获取用户的全部份额
        uint256 ibalance = balanceOf(msg.sender);
        // 确认取出的份额<=用户全部份额
        require(_shares <= ibalance, "insufficient balance");

        // 可能来自cTokens的价值过高
        // Could have over value from cTokens
        // 池子总量 = 当前合约在(Compound合约,bZx合约,dydx合约,Aave合约,DAI合约)中的DAI余额
        pool = _calcPoolValueInToken();
        // 计算余额之前先兑换
        // Calc to redeem before updating balances
        // 从池子中取出的数额 = 池子总量 * 取出的份额 / 总份额
        uint256 r = (pool.mul(_shares)).div(_totalSupply);

        // 用户的余额 = 用户的余额 - 取出的份额
        _balances[msg.sender] = _balances[msg.sender].sub(
            _shares,
            "redeem amount exceeds balance"
        );
        // 总份额 = 总分额 - 取出的份额
        _totalSupply = _totalSupply.sub(_shares);

        // 触发销毁事件
        emit Transfer(msg.sender, address(0), _shares);

        // 检查余额
        // Check balance
        // b = 当前合约在DAI合约中的余额
        uint256 b = IERC20(token).balanceOf(address(this));
        // 如果 当前合约在DAI合约中的余额 < 从池子中取出的数额
        if (b < r) {
            // 从当前的投资策略中赎回资产,DAI数额为 从池子中取出的数额 - 当前合约在DAI合约中的余额(当前合约不足的部分)
            _withdrawSome(r.sub(b));
        }

        // 将DAI发送给用户数量为从池子中取出的数额
        IERC20(token).transfer(msg.sender, r);
        // 重新计算池子总量
        pool = _calcPoolValueInToken();
    }

    /**
     * @dev 赎回方法
     * @param _shares 赎回的份额
     */
    // Redeem any invested tokens from the pool
    function redeem(uint256 _shares) external nonReentrant {
        require(_shares > 0, "withdraw must be greater than 0");

        // 获取用户的全部份额
        uint256 ibalance = balanceOf(msg.sender);
        // 确认取出的份额<=用户全部份额
        require(_shares <= ibalance, "insufficient balance");

        // 可能来自cTokens的价值过高
        // Could have over value from cTokens
        // 池子总量 = 当前合约在(Compound合约,bZx合约,dydx合约,Aave合约,DAI合约)中的DAI余额
        pool = calcPoolValueInToken();
        // 计算余额之前先兑换
        // Calc to redeem before updating balances
        // 从池子中取出的数额 = 池子总量 * 取出的份额 / 总份额
        uint256 r = (pool.mul(_shares)).div(_totalSupply);

        // 用户的余额 = 用户的余额 - 取出的份额
        _balances[msg.sender] = _balances[msg.sender].sub(
            _shares,
            "redeem amount exceeds balance"
        );
        // 总份额 = 总分额 - 取出的份额
        _totalSupply = _totalSupply.sub(_shares);

        // 触发销毁事件
        emit Transfer(msg.sender, address(0), _shares);

        // 检查余额
        // Check ETH balance
        // b = 当前合约在DAI合约中的余额
        uint256 b = IERC20(token).balanceOf(address(this));
        // 当前策略
        Lender newProvider = provider;
        // 如果 当前合约在DAI合约中的余额 < 从池子中取出的数额
        if (b < r) {
            // 推荐策略
            newProvider = recommend();
            // 如果当前执行的策略不是推荐的策略
            if (newProvider != provider) {
                // 提款全部
                _withdrawAll();
            } else {
                // 从当前的投资策略中赎回资产,DAI数额为 从池子中取出的数额 - 当前合约在DAI合约中的余额(当前合约不足的部分)
                _withdrawSome(r.sub(b));
            }
        }
        // 向用户发送数额为从池子中取出的数额的DAI
        IERC20(token).safeTransfer(msg.sender, r);

        // 如果当前执行的策略不是推荐的策略
        if (newProvider != provider) {
            // 内部移仓方法
            _rebalance(newProvider);
        }
        // 重新计算池子总量
        pool = calcPoolValueInToken();
    }
    /**
     * @dev 从当前的投资策略中赎回资产
     * @param _amount 赎回的DAI数额
     */
    function _withdrawSome(uint256 _amount) internal {
        // 如果 当前策略为COMPOUND, 赎回DAI
        if (provider == Lender.COMPOUND) {
            _withdrawSomeCompound(_amount);
        }
        // 如果 当前策略为AAVE, 赎回DAI
        if (provider == Lender.AAVE) {
            require(balanceAave() >= _amount, "insufficient funds");
            _withdrawAave(_amount);
        }
        // 如果 当前策略为DYDX, 赎回DAI
        if (provider == Lender.DYDX) {
            require(balanceDydx() >= _amount, "insufficient funds");
            _withdrawDydx(_amount);
        }
        // 如果 当前策略为bZx, 赎回DAI
        if (provider == Lender.FULCRUM) {
            _withdrawSomeFulcrum(_amount);
        }
    }

    /**
     * @dev 内部提款全部方法
     * @notice 将Compound,dydx,Aave,bZx四个项目的余额都取出
     */
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

    /**
     * @dev 从AAVE项目中赎回资产
     * @param _amount 赎回的DAI数额
     * @notice 调用AAVE的赎回方法,赎回DAI
     */
    function _withdrawAave(uint256 amount) internal {
        AToken(aaveToken).redeem(amount);
    }

    /**
     * @dev 从bZx项目中赎回资产
     * @param _amount 赎回的iToken数额
     * @notice 调用bZx的赎回方法,赎回DAI
     */
    function _withdrawFulcrum(uint256 amount) internal {
        require(
            Fulcrum(fulcrum).burn(address(this), amount) > 0,
            "FULCRUM: withdraw failed"
        );
    }

    /**
     * @dev 从bZx项目中赎回资产
     * @param _amount 赎回的DAI数额
     */
    // 1999999614570950845
    function _withdrawSomeFulcrum(uint256 _amount) internal {
        // 当前合约在bZx合约中的iToken余额
        // Balance of fulcrum tokens, 1 iDAI = 1.00x DAI
        uint256 b = balanceFulcrum(); // 1970469086655766652
        // 返回bZx DAI iToken合约中的底层资产(DAI)余额
        // Balance of token in fulcrum
        uint256 bT = balanceFulcrumInToken(); // 2000000803224344406
        // 确认 iToken合约中的底层资产(DAI)余额 >= 赎回的DAI数额
        require(bT >= _amount, "insufficient funds");
        // 可能会有意外的舍入错误
        // can have unintentional rounding errors
        // 取出的iToken数额 = 当前合约在bZx合约中的iToken余额 * 赎回的DAI数额 / iToken合约中的底层资产(DAI)余额 + 1
        uint256 amount = (b.mul(_amount)).div(bT).add(1);
        // 从bZx项目中赎回DAI
        _withdrawFulcrum(amount);
    }

    /**
     * @dev 从Compound项目中赎回资产
     * @param _amount 赎回的CToken数额
     */
    function _withdrawCompound(uint256 amount) internal {
        // 确认 调用Compound合约的赎回方法,赎回指定数额的CToken,返回值为0代表没有错误
        require(
            Compound(compound).redeem(amount) == 0,
            "COMPOUND: withdraw failed"
        );
    }

    /**
     * @dev 从Compound项目中赎回资产
     * @param _amount 赎回的DAI数额
     */
    function _withdrawSomeCompound(uint256 _amount) internal {
        // 当前合约在Compound合约中的CToken余额
        uint256 b = balanceCompound();
        // Compound合约中的底层资产(DAI)余额
        uint256 bT = balanceCompoundInToken();
        // 确认Compound合约中的底层资产(DAI)余额 大于等于 赎回的DAI数额
        require(bT >= _amount, "insufficient funds");
        // 可能会有意外的舍入错误
        // can have unintentional rounding errors
        // 取出的CToken数额 = 当前合约在Compound合约中的CToken余额 * 赎回的DAI数额 / Compound合约中的底层资产(DAI)余额 + 1
        uint256 amount = (b.mul(_amount)).div(bT).add(1);
        // 从Compound项目中赎回DAI
        _withdrawCompound(amount);
    }

    /**
     * @dev 从dydx项目中赎回资产
     * @param _amount 赎回的DAI数额
     */
    function _withdrawDydx(uint256 amount) internal {
        // 当前合约在dydx项目中的余额
        Info[] memory infos = new Info[](1);
        infos[0] = Info(address(this), 0);

        // 制作赎回资产需要的参数
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

        // 赎回DAI资产
        DyDx(dydx).operate(infos, args);
    }

    ///////////////////////////////////获取余额////////////////////////////////

    /**
     * @dev 返回当前合约在DAI合约中的余额
     */
    function _balance() internal view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @dev 返回当前合约在DAI合约中的余额
     */
    function balance() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @dev 返回Aave合约中的底层资产(DAI)余额
     */
    function _balanceAave() internal view returns (uint256) {
        return IERC20(aaveToken).balanceOf(address(this));
    }

    /**
     * @dev 返回Aave合约中的底层资产(DAI)余额
     */
    function balanceAave() public view returns (uint256) {
        return IERC20(aaveToken).balanceOf(address(this));
    }

    /**
     * @dev 当前合约在bZx合约中的iToken余额
     */
    function _balanceFulcrum() internal view returns (uint256) {
        return IERC20(fulcrum).balanceOf(address(this));
    }

    /**
     * @dev 当前合约在bZx合约中的iToken余额
     */
    function balanceFulcrum() public view returns (uint256) {
        return IERC20(fulcrum).balanceOf(address(this));
    }

    /**
     * @dev 返回bZx DAI iToken合约中的底层资产(DAI)余额
     */
    function _balanceFulcrumInToken() internal view returns (uint256) {
        // 当前合约在bZx合约中的iToken余额
        uint256 b = balanceFulcrum();
        if (b > 0) {
            // bZx DAI iToken合约中的底层资产(DAI)余额
            b = Fulcrum(fulcrum).assetBalanceOf(address(this));
        }
        return b;
    }

    /**
     * @dev 返回bZx DAI iToken合约中的底层资产(DAI)余额
     */
    function balanceFulcrumInToken() public view returns (uint256) {
        // 当前合约在bZx合约中的iToken余额
        uint256 b = balanceFulcrum();
        if (b > 0) {
            // bZx DAI iToken合约中的底层资产(DAI)余额
            b = Fulcrum(fulcrum).assetBalanceOf(address(this));
        }
        return b;
    }

    /**
     * @dev 当前合约在Compound合约中的CToken余额
     */
    function _balanceCompound() internal view returns (uint256) {
        return IERC20(compound).balanceOf(address(this));
    }

    /**
     * @dev 当前合约在Compound合约中的CToken余额
     */
    function balanceCompound() public view returns (uint256) {
        return IERC20(compound).balanceOf(address(this));
    }

    /**
     * @dev Compound合约中的底层资产(DAI)余额
     */
    function _balanceCompoundInToken() internal view returns (uint256) {
        // 当前合约在Compound合约中的CToken余额
        // Mantisa 1e18 to decimals
        uint256 b = balanceCompound();
        if (b > 0) {
            // CToken余额 * 207063625310209065157095094 / 1e18
            b = b.mul(Compound(compound).exchangeRateStored()).div(1e18);
        }
        return b;
    }

    /**
     * @dev Compound合约中的底层资产(DAI)余额
     */
    function balanceCompoundInToken() public view returns (uint256) {
        // 当前合约在Compound合约中的CToken余额
        // Mantisa 1e18 to decimals
        uint256 b = balanceCompound();
        if (b > 0) {
            // CToken余额 * 207063625310209065157095094 / 1e18
            b = b.mul(Compound(compound).exchangeRateStored()).div(1e18);
        }
        return b;
    }

    /**
     * @dev 当前合约在dydx合约中的余额
     */
    function _balanceDydx() internal view returns (uint256) {
        Wei memory bal = DyDx(dydx).getAccountWei(
            Info(address(this), 0),
            dToken
        );
        return bal.value;
    }

    /**
     * @dev 当前合约在dydx合约中的余额
     */
    function balanceDydx() public view returns (uint256) {
        Wei memory bal = DyDx(dydx).getAccountWei(
            Info(address(this), 0),
            dToken
        );
        return bal.value;
    }

    ///////////////////////////////////策略////////////////////////////////

    /**
     * @dev 推荐策略
     * @notice 根据调用apr合约找到最高apr的策略
     */
    function recommend() public view returns (Lender) {
        // 根据调用apr合约找到最高apr的策略
        (
            ,
            uint256 capr, // 当前值:0
            uint256 iapr, // 当前值:0
            uint256 aapr, // 当前值:17265499454748079
            uint256 dapr // 当前值:490873165375945
        ) = IIEarnManager(apr).recommend(token);
        uint256 max = 0;
        // 找到最大值
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
        // 出借策略 = none
        Lender newProvider = Lender.NONE;
        // 选择最高apr的出借策略
        if (max == capr) {
            newProvider = Lender.COMPOUND;
        } else if (max == iapr) {
            newProvider = Lender.FULCRUM;
        } else if (max == aapr) {
            newProvider = Lender.AAVE;
        } else if (max == dapr) {
            newProvider = Lender.DYDX;
        }
        // 返回新策略
        return newProvider;
    }

    /**
     * @dev 移仓方法
     * @notice 根据调用apr合约找到最高apr的策略,如果当前执行的策略不是推荐的策略,向推荐策略对应的项目存款
     */
    function rebalance() public {
        // 获取推荐的策略
        Lender newProvider = recommend();

        // 如果当前执行的策略不是推荐的策略
        if (newProvider != provider) {
            // 提款全部
            _withdrawAll();
        }

        // 如果当前合约的DAI余额>0
        if (balance() > 0) {
            // 向推荐策略对应的项目存款
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

    /**
     * @dev 内部移仓方法
     * @param newProvider 新策略名称
     */
    // 仅内部重新平衡，以便节省赎回操作的gas
    // Internal only rebalance for better gas in redeem
    function _rebalance(Lender newProvider) internal {
        // 如果当前合约的DAI余额>0
        if (_balance() > 0) {
            // 向指定的新策略对应的项目存款
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
        // 将当前策略设置为指定的新策略
        provider = newProvider;
    }

    /**
     * @dev 计算资产总和
     * @notice Compound合约,bZx合约,dydx合约,Aave合约,DAI合约
     */
    function _calcPoolValueInToken() internal view returns (uint256) {
        // 返回 当前合约在(Compound合约,bZx合约,dydx合约,Aave合约,DAI合约)中的DAI余额
        return
            _balanceCompoundInToken()
                .add(_balanceFulcrumInToken())
                .add(_balanceDydx())
                .add(_balanceAave())
                .add(_balance());
    }

    /**
     * @dev 计算资产总和
     * @notice Compound合约,bZx合约,dydx合约,Aave合约,DAI合约
     */
    function calcPoolValueInToken() public view returns (uint256) {
        // 返回 当前合约在(Compound合约,bZx合约,dydx合约,Aave合约,DAI合约)中的DAI余额
        return
            balanceCompoundInToken()
                .add(balanceFulcrumInToken())
                .add(balanceDydx())
                .add(balanceAave())
                .add(balance());
    }

    /**
     * @dev 计算每份额对应资产数量
     */
    function getPricePerFullShare() public view returns (uint256) {
        // 池子数额 = 计算资产总和
        uint256 _pool = calcPoolValueInToken();
        // 返回 池子数额 * 1e18 / 总份额
        return _pool.mul(1e18).div(_totalSupply);
    }

}
