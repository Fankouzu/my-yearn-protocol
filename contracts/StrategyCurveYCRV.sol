/**
 *Submitted for verification at Etherscan.io on 2020-08-14
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.5.17;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function decimals() external view returns (uint);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;

        return c;
    }
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

library Address {
    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != 0x0 && codehash != accountHash);
    }
    function toPayable(address account) internal pure returns (address payable) {
        return address(uint160(account));
    }
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-call-value
        (bool success, ) = recipient.call.value(amount)("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
}

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
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }
    function callOptionalReturn(IERC20 token, bytes memory data) private {
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

interface Controller {
    function vaults(address) external view returns (address);
    function rewards() external view returns (address);
}

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
    function deposit(uint) external;
    function balanceOf(address) external view returns (uint);
    function withdraw(uint) external;
}

interface Mintr {
    function mint(address) external;
}

interface Uni {
    function swapExactTokensForTokens(uint, uint, address[] calldata, address, uint) external;
}

interface yERC20 {
  function deposit(uint256 _amount) external;
  function withdraw(uint256 _amount) external;
}

interface ICurveFi {

  function get_virtual_price() external view returns (uint);
  function add_liquidity(
    uint256[4] calldata amounts,
    uint256 min_mint_amount
  ) external;
  function remove_liquidity_imbalance(
    uint256[4] calldata amounts,
    uint256 max_burn_amount
  ) external;
  function remove_liquidity(
    uint256 _amount,
    uint256[4] calldata amounts
  ) external;
  function exchange(
    int128 from, int128 to, uint256 _from_amount, uint256 _min_to_amount
  ) external;
}

contract StrategyCurveYCRV {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // yCRV地址
    address constant public want = address(0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8); 
    // Curve.fi: yCrv Gauge
    address constant public pool = address(0xFA712EE4788C042e2B7BB55E6cb8ec569C4530c1);
    // Curve.fi: Token Minter
    address constant public mintr = address(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0);

    address constant public crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address constant public uni = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // used for crv <> weth <> dai route
    
    address constant public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address constant public ydai = address(0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01);
    address constant public curve = address(0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51);
    
    // 策略返佣: 500/10000=5%
    uint public performanceFee = 500;
    uint constant public performanceMax = 10000;
    
    // 取款手续费: 50/10000=0.5%
    uint public withdrawalFee = 50;
    uint constant public withdrawalMax = 10000;
    
    address public governance;
    address public controller;
    address public strategist;
    
    /**
     * @dev 构造函数
     * @param _controller 控制器
     * @notice 治理地址及策略员地址为msg.sender
     */
    constructor(address _controller) public {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
    }
    
    /**
     * @dev 返回策略名称
     */
    function getName() external pure returns (string memory) {
        return "StrategyCurveYCRV";
    }
    
    /**
     * @dev 设置新策略员
     * @param _strategist 策略员地址 
     * @notice 治理地址可以设置新策略员得治
     */
    function setStrategist(address _strategist) external {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }
    
    /**
     * @dev 设置取款手续费
     * @param _withdrawalFee 取款手续费
     * @notice 治理地址可以设置取款手续费
     */
    function setWithdrawalFee(uint _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        withdrawalFee = _withdrawalFee;
    }
    
    /**
     * @dev 设置策略佣金
     * @param _performanceFee 策略佣金
     * @notice 治理地址可以设置取款佣金
     */
    function setPerformanceFee(uint _performanceFee) external {
        require(msg.sender == governance, "!governance");
        performanceFee = _performanceFee;
    }
    
    /**
     * @dev 存款函数
     * @notice 把本合约中所有的yCRV存入curve的gauge中
     */
    function deposit() public {
        // 查询本合约中yCRV余额
        uint _want = IERC20(want).balanceOf(address(this));
        // 如果余额大于0
        if (_want > 0) {
            // approve curve的gauge(抵押池)
            IERC20(want).safeApprove(pool, 0);
            IERC20(want).safeApprove(pool, _want);
            // 存入curve的抵押池中
            Gauge(pool).deposit(_want);
        }
        
    }
    
    /**
     * @dev 取款函数(特殊)
     * @param _asset 所需取出的token地址
     * @notice 只有控制器才能调用此程序,取出所有的_asset token的到控制器地址(_asset不含yCrv、crv、ydai、dai)
     */
    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        require(crv != address(_asset), "crv");
        require(ydai != address(_asset), "ydai");
        require(dai != address(_asset), "dai");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }
    
    /**
     * @dev yCRV取款函数
     * @param _amount 取出数量
     * @notice 只有控制器才能调用此程序
     */
    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint _amount) external {
        require(msg.sender == controller, "!controller");
        // 获取合约中yCRV的数量
        uint _balance = IERC20(want).balanceOf(address(this));
        // 如果合约中yCRV的数量小于需要取出的数量,那就需要去curve的gauge中取回一些
        if (_balance < _amount) {
            // curve的gauge取款函数,取出的值正好为上面不足的额度(即_amount-_balance)
            _amount = _withdrawSome(_amount.sub(_balance));
            // 这步是重复的 _amount = _amount - _balance + _balance
            _amount = _amount.add(_balance);
        }        
        // 取款手续费 _fee = _amount * 手续费百分比
        uint _fee = _amount.mul(withdrawalFee).div(withdrawalMax);
        // 把手续费发送到controller里设置的奖励地址
        IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
        // 获取保险库地址
        address _vault = Controller(controller).vaults(address(want));
        // 额外校验,避免_vault地址是销毁地址,造成资金损失
        // additional protection so we don't burn the funds
        require(_vault != address(0), "!vault"); 
        // 扣除手续费后,剩余yCRV打入保险库中
        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
    }
    
    /**
     * @dev 取款函数
     * @notice 取出所有yCRV,一般用在迁移策略的时候
     */
    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        _withdrawAll();
        
        // 本合约中所有yCRV的数量
        balance = IERC20(want).balanceOf(address(this));
        
        address _vault = Controller(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);
    }

    /**
     * @dev 取款函数
     * @notice 从curve的gauge中取出所有yCRV
     */
    function _withdrawAll() internal {
        // 从y池 gauge中取出该合约所拥有的所有yCRV
        Gauge(pool).withdraw(Gauge(pool).balanceOf(address(this)));
    }
    
    /**
     * @dev 收割函数
     * @notice 定期收割yield farming token,可以由策略员,或者社区治理地址调用
     */
    function harvest() public {
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        // 从y池 gauge中收割crv
        Mintr(mintr).mint(pool);
        // 获取该合约地址中的crv数量
        uint _crv = IERC20(crv).balanceOf(address(this));
        // 如果crv数量大于0
        if (_crv > 0) {
            IERC20(crv).safeApprove(uni, 0);
            IERC20(crv).safeApprove(uni, _crv);
            
            address[] memory path = new address[](3);
            path[0] = crv;
            path[1] = weth;
            path[2] = dai;
            
            // 调用uniswap,把crv换成dai,路径为crv > eth > dai
            Uni(uni).swapExactTokensForTokens(_crv, uint(0), path, address(this), now.add(1800));
        }

        // 获取该合约地址中的dai数量
        uint _dai = IERC20(dai).balanceOf(address(this));
        // 如果dai数量大于0
        if (_dai > 0) {
            IERC20(dai).safeApprove(ydai, 0);
            IERC20(dai).safeApprove(ydai, _dai);
            // 存入ydai的vault中
            yERC20(ydai).deposit(_dai);
        }

        // 获取该合约地址中的ydai数量
        uint _ydai = IERC20(ydai).balanceOf(address(this));
        if (_ydai > 0) {
            IERC20(ydai).safeApprove(curve, 0);
            IERC20(ydai).safeApprove(curve, _ydai);
            // 存入curve的y池中,此时ydai转换为yCRV
            ICurveFi(curve).add_liquidity([_ydai,0,0,0],0);
        }

        // 获取该合约地址中的yCRV数量
        uint _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            // 策略费 = yCRV数量 * 策略费百分比
            uint _fee = _want.mul(performanceFee).div(performanceMax);
            // 把策略费转到奖励池中
            IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
            // 扣除策略费后,剩下的yCRV全部存入curve的gauge中
            deposit();
        }
    }
    
    /**
     * @dev curve取款方法
     * @param _amount token数量
     * @notice 从curve抵押池中取出yCRV
     */
    function _withdrawSome(uint256 _amount) internal returns (uint) {
        Gauge(pool).withdraw(_amount);
        return _amount;
    }
    
    /**
     * @dev 查询yCRV数量
     */
    function balanceOfWant() public view returns (uint) {
        return IERC20(want).balanceOf(address(this));
    }
    
    /**
     * @dev 查询在抵押于curve中y池 gauge的yCRV数量
     */
    function balanceOfPool() public view returns (uint) {
        return Gauge(pool).balanceOf(address(this));
    }
    
    /**
     * @dev 返回yCRV总数量
     * @notice 包含合约中的和抵押在curve中的
     */
    function balanceOf() public view returns (uint) {
        return balanceOfWant()
               .add(balanceOfPool());
    }
    
    /**
     * @dev 设置治理地址
     * @notice 只能有老治理地址设定
     */
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }
    
    /**
     * @dev 设置控制器
     * @notice 只能有老治理地址设定
     */
    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
}
