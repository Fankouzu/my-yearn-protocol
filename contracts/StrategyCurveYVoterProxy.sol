/**
 *Submitted for verification at Etherscan.io on 2020-10-11
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.5.17;


/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see {ERC20Detailed}.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     *
     * _Available since v2.4.0._
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     *
     * _Available since v2.4.0._
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     *
     * _Available since v2.4.0._
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
        // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
        // for accounts without code, i.e. `keccak256('')`
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != accountHash && codehash != 0x0);
    }

    /**
     * @dev Converts an `address` into `address payable`. Note that this is
     * simply a type cast: the actual underlying value is not changed.
     *
     * _Available since v2.4.0._
     */
    function toPayable(address account) internal pure returns (address payable) {
        return address(uint160(account));
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     *
     * _Available since v2.4.0._
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-call-value
        (bool success, ) = recipient.call.value(amount)("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
}

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for ERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves.

        // A Solidity high level call has three parts:
        //  1. The target address is checked to verify it contains contract code
        //  2. The call itself is made, and success asserted
        //  3. The return value is decoded, which in turn checks the size of the returned data.
        // solhint-disable-next-line max-line-length
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

//
interface IController {
    function withdraw(address, uint256) external;

    function balanceOf(address) external view returns (uint256);

    function earn(address, uint256) external;

    function want(address) external view returns (address);

    function rewards() external view returns (address);

    function vaults(address) external view returns (address);

    function strategies(address) external view returns (address);
}

//
interface Gauge {
    function deposit(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function withdraw(uint256) external;
}

//
interface Mintr {
    function mint(address) external;
}

//
interface Uni {
    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external;
}

//
interface ICurveFi {
    function get_virtual_price() external view returns (uint256);

    function add_liquidity(
    // sBTC pool
        uint256[3] calldata amounts,
        uint256 min_mint_amount
    ) external;

    function add_liquidity(
    // bUSD pool
        uint256[4] calldata amounts,
        uint256 min_mint_amount
    ) external;

    function remove_liquidity_imbalance(uint256[4] calldata amounts, uint256 max_burn_amount) external;

    function remove_liquidity(uint256 _amount, uint256[4] calldata amounts) external;

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

//
// NOTE: Basically an alias for Vaults
interface yERC20 {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function getPricePerFullShare() external view returns (uint256);
}

//
interface VoterProxy {
    function withdraw(
        address _gauge,
        address _token,
        uint256 _amount
    ) external returns (uint256);

    function balanceOf(address _gauge) external view returns (uint256);

    function withdrawAll(address _gauge, address _token) external returns (uint256);

    function deposit(address _gauge, address _token) external;

    function harvest(address _gauge) external;

    function lock() external;
}

/**
 * @title curve.fi/y LP策略合约
 * @author 噷崖
 * @dev  最新策略地址:0x07DB4B9b3951094B9E278D336aDf46a036295DE7   相比之前策略 harvest() 增加锁定
 */
contract StrategyCurveYVoterProxy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // yCRV地址 Curve.fi yDAI/yUSDC/yUSDT/yTUSD (yDAI+yUSDC+yUSDT+yTUSD)  yCRV可以理解为4种稳定币的指标
    address public constant want = address(0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8);
    // Curve DAO Token (CRV)
    address public constant crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    // Uniswap V2: Router 2
    address public constant uni = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    // WETH
    address public constant weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // used for crv <> weth <> dai route
    // Dai Stablecoin (DAI)
    address public constant dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    // iearn DAI (yDAI)
    address public constant ydai = address(0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01);
    // Curve.fi: y Swap
    address public constant curve = address(0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51);
    // Curve.fi: yCrv Gauge
    address public constant gauge = address(0xFA712EE4788C042e2B7BB55E6cb8ec569C4530c1);
    // yEarn CurveYCRVVoter
    address public constant voter = address(0xF147b8125d2ef93FB6965Db97D6746952a133934);

    uint256 public keepCRV = 1000;  //保留的crv比例，可以由governance修改
    uint256 public constant keepCRVMax = 10000; //用于计算保留比例

    uint256 public performanceFee = 500; //策略员的收益比例
    uint256 public constant performanceMax = 10000;//用于计算策略员的收益比例

    uint256 public withdrawalFee = 50;//提现手续费
    uint256 public constant withdrawalMax = 10000;//用于计算提现手续费

    address public proxy;  // yEarn StrategyProxy 0x7A1848e7847F3f5FfB4d8e63BdB9569db535A4f0  相比上版本修改为动态设置

    address public governance; //治理地址 0x2D407dDb06311396fE14D4b49da5F0471447d45C
    address public controller; //控制器 0x9E65Ad11b299CA0Abefc2799dDB6314Ef2d91080
    address public strategist; //策略员地址 0xd0aC37E3524F295D141d3839d5ed5F26A40b589D 为CrvStrategyKeep3r合约地址

    /**
     * @dev 构造函数
     * @param _controller 控制器合约地址 传值为 0x9e65ad11b299ca0abefc2799ddb6314ef2d91080
     */
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
    function setStrategist(address _strategist) external {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }

    /**
    * @dev 设置保留的crv比例
    * @param _keepCRV 比例值
    * @notice 只能由治理地址设置
    */
    function setKeepCRV(uint256 _keepCRV) external {
        require(msg.sender == governance, "!governance");
        keepCRV = _keepCRV;
    }

    /**
    * @dev 设置提现手续费
    * @param _withdrawalFee 提现手续费
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
     * @dev 设置代理合约地址
     * @notice 只能由治理地址设置
     */
    function setProxy(address _proxy) external {
        require(msg.sender == governance, "!governance");
        proxy = _proxy;
    }

    /**
     * @dev 存款方法
     * @notice 将本合约中的ycrv通过proxy合约存入gauge中获取收益
     */
    function deposit() public {
        // 当前合约在yCrv合约中的余额
        uint256 _want = IERC20(want).balanceOf(address(this));
        // 如果余额大于0
        if (_want > 0) {
            // 将yCrv余额批准给yEarn StrategyProxy
            IERC20(want).safeTransfer(proxy, _want);
            // 通过proxy合约存入gauge中获取收益
            VoterProxy(proxy).deposit(gauge, want);
        }
    }

    /**
     * @dev 从本合约中提现某种token的全部余额到controller控制器合约
     * @param _asset 代币合约地址
     * @notice 不能提取 want，crv，ydai，dai Controller only function for creating additional rewards from dust
     * @return balance 提现金额
     */
    function withdraw(IERC20 _asset) external returns (uint256 balance) {
        //仅controller可以操作
        require(msg.sender == controller, "!controller");
        //限定不能提取want，crv，ydai，dai
        require(want != address(_asset), "want");
        require(crv != address(_asset), "crv");
        require(ydai != address(_asset), "ydai");
        require(dai != address(_asset), "dai");
        //获取对应token的余额
        balance = _asset.balanceOf(address(this));
        //转账给controller
        _asset.safeTransfer(controller, balance);
    }

    /**
    * @dev yCRV提现
    * @param _amount 提现金额
    * @notice 仅controller可以操作 Withdraw partial funds, normally used with a vault withdrawal
    */
    function withdraw(uint256 _amount) external {
        //仅controller可以操作
        require(msg.sender == controller, "!controller");
        // 获取合约中yCRV的数量
        uint256 _balance = IERC20(want).balanceOf(address(this));
        // 如果合约中yCRV的数量小于提现金额,差额需要去curve的gauge中取回
        if (_balance < _amount) {
            //计算差额并提取
            _amount = _withdrawSome(_amount.sub(_balance));
            //重新计算提取金额，防止提取的差额错误
            _amount = _amount.add(_balance);
        }
        // 提现手续费 _fee = _amount * 0.05
        uint256 _fee = _amount.mul(withdrawalFee).div(withdrawalMax);
        // 把手续费发送到controller里设置的奖励地址
        IERC20(want).safeTransfer(IController(controller).rewards(), _fee);
        // 获取保险库地址
        address _vault = IController(controller).vaults(address(want));
        //判断获取的保险库地址是否有效  additional protection so we don't burn the funds
        require(_vault != address(0), "!vault");
        // 扣除手续费后,剩余yCRV打入保险库中
        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
    }

    /**
     * @dev 取款函数
     * @notice 取出所有yCRV,一般用在迁移策略的时候 Withdraw all funds, normally used when migrating strategies
     */
    function withdrawAll() external returns (uint256 balance) {
        //仅controller可以操作
        require(msg.sender == controller, "!controller");
        //调用内部提现
        _withdrawAll();

        // 本合约中所有yCRV的数量
        balance = IERC20(want).balanceOf(address(this));
        // 获取保险库地址 0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c
        address _vault = IController(controller).vaults(address(want));
        //判断获取的保险库地址是否有效  additional protection so we don't burn the funds
        require(_vault != address(0), "!vault");
        // yCRV打入保险库中
        IERC20(want).safeTransfer(_vault, balance);
    }


    /**
     * @dev 内部调用提现函数
     * @notice 从curve的gauge中取出所有yCRV
     */
    function _withdrawAll() internal {
        // 从y池 gauge中取出该合约所拥有的所有yCRV
        VoterProxy(proxy).withdrawAll(gauge, want);
    }

    /**
     * @dev 收获方法
     * @notice 获取crv收益，兑换为ycrv，再存入curve的gauge中再获取收益
     */
    function harvest() public {
        // 只能从策略账户或治理账户调用
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        // 通过 VoterProxy 代理合约调用curve的gauge合约获取crv收益
        VoterProxy(proxy).harvest(gauge);
        //当前合约的crv余额
        uint256 _crv = IERC20(crv).balanceOf(address(this));
        //如果当前合约的crv余额大于0
        if (_crv > 0) {
            //10%的crv转给voter，用于投票获取2.5倍奖励
            uint256 _keepCRV = _crv.mul(keepCRV).div(keepCRVMax);
            IERC20(crv).safeTransfer(voter, _keepCRV);
            //计算剩余crv
            _crv = _crv.sub(_keepCRV);
            //授权给uni对应的_crv数量
            IERC20(crv).safeApprove(uni, 0);
            IERC20(crv).safeApprove(uni, _crv);
            //定义路径 crv->weth->dai
            address[] memory path = new address[](3);
            path[0] = crv;
            path[1] = weth;
            path[2] = dai;
            //执行uni的兑换方法
            Uni(uni).swapExactTokensForTokens(_crv, uint256(0), path, address(this), now.add(1800));
        }
        //获取本合约中dai余额
        uint256 _dai = IERC20(dai).balanceOf(address(this));
        if (_dai > 0) {
            //授权给ydai合约
            IERC20(dai).safeApprove(ydai, 0);
            IERC20(dai).safeApprove(ydai, _dai);
            //存款到ydai合约中换取ydai
            yERC20(ydai).deposit(_dai);
        }
        //获取本合约中ydai余额
        uint256 _ydai = IERC20(ydai).balanceOf(address(this));
        if (_ydai > 0) {
            //授权给curve合约
            IERC20(ydai).safeApprove(curve, 0);
            IERC20(ydai).safeApprove(curve, _ydai);
            //向curve合约提供流动性获取ycrv代币
            ICurveFi(curve).add_liquidity([_ydai, 0, 0, 0], 0);
        }
        //获取本合约中ycrv余额
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            // 计算策略费 0.05%=500/10000
            uint256 _fee = _want.mul(performanceFee).div(performanceMax);
            // 把策略费转到controller中设置的奖励池中
            IERC20(want).safeTransfer(IController(controller).rewards(), _fee);
            //讲此次获取的ycrv再次进行存款操作，获取crv收益
            deposit();
        }
        //相比旧版本怎加此lock()方法，将上面保留的10%crv，通过 escrow（合约地址0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2）换取veCRV
        /*
        *
        * function lock() external {
        *    uint256 amount = IERC20(crv).balanceOf(address(proxy));
        *     if (amount > 0) proxy.increaseAmount(amount);
        * }
        */
        VoterProxy(proxy).lock();
    }

    /**
     * @dev 从投资中部分提现方法
     * @param _amount 提现的金额
     * @notice
     */
    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        return VoterProxy(proxy).withdraw(gauge, want, _amount);
    }

    /**
     * @dev 获取本合约中ycrv的余额
     * @notice
     */
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    /**
     * @dev proxy在gauge中的ycrv余额
     * @notice
     */
    function balanceOfPool() public view returns (uint256) {
        return VoterProxy(proxy).balanceOf(gauge);
    }

    /**
     * @dev 获取余额（合约中ycrv的余额+proxy在gauge中的ycrv余额）
     * @notice
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    /**
    * @dev 设置治理地址 仅限原有治理地址调用
    * @notice
    */
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    /**
     * @dev 设置控制器地址 仅限原有治理地址调用
     * @notice
     */
    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
}