/**
 *Submitted for verification at Etherscan.io on 2020-09-01
 */

pragma solidity ^0.5.16;
import "./common.sol";

// WETH保险库合约 0xe1237aA7f535b0CC33Fd973D66cBf830354D16c7
contract yVault is ERC20, ERC20Detailed {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    // Wrapped Ether
    IERC20 public token; // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2

    // 最小值 / 最大值 = 99.9%
    uint256 public min = 9990;
    uint256 public constant max = 10000;

    // 治理地址
    address public governance; // 0xfeb4acf3df3cdea7399794d0869ef76a6efaff52 proxy
    // 控制器合约
    address public controller; // 0x9e65ad11b299ca0abefc2799ddb6314ef2d91080

    /**
     * @dev 构造函数
     * @param _token 基础资产WETH
     * @param _controller 控制器
     */
    constructor(address _token, address _controller)
        public
        // 用编码的方法将原来token的名字和缩写加上前缀
        ERC20Detailed(
            string(abi.encodePacked("yearn ", ERC20Detailed(_token).name())),
            string(abi.encodePacked("y", ERC20Detailed(_token).symbol())),
            ERC20Detailed(_token).decimals()
        )
    {
        token = IERC20(_token);
        governance = msg.sender;
        controller = _controller;
    }

    /// @notice 当前合约在WETH的余额,加上控制器中当前合约的余额
    function balance() public view returns (uint256) {
        return token.balanceOf(address(this)).add(Controller(controller).balanceOf(address(token)));
    }

    /// @notice 设置最小值
    function setMin(uint256 _min) external {
        require(msg.sender == governance, "!governance");
        min = _min;
    }

    /// @notice 设置治理账号
    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    /// @notice 设置控制器
    function setController(address _controller) public {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    /**
     * @dev 空闲余额
     * @notice 当前合约在WETH的余额的95%
     */
    // 此处的自定义逻辑用于允许借用保险库的数量
    // 设置最低要求，以保持小额取款便宜
    // Custom logic in here for how much the vault allows to be borrowed
    // Sets minimum required on-hand to keep small withdrawals cheap
    function available() public view returns (uint256) {
        // 当前合约在WETH的余额 * 99.9%
        return token.balanceOf(address(this)).mul(min).div(max);
    }

    /**
     * @dev 赚钱方法
     * @notice 将空闲余额发送到控制器,再调用控制器的赚钱方法
     */
    function earn() public {
        uint256 _bal = available();
        token.safeTransfer(controller, _bal);
        Controller(controller).earn(address(token), _bal);
    }

    /**
     * @dev 全部存款方法
     * @notice 将调用者的全部WETH作为参数发送到存款方法
     */
    function depositAll() external {
        deposit(token.balanceOf(msg.sender));
    }

    /**
     * @dev 存款方法
     * @param _amount 存款数额
     * @notice 当前合约在WETH的余额发送到当前合约,并铸造份额币
     */
    function deposit(uint256 _amount) public {
        // 池子数量 = 当前合约和控制器合约在WETH的余额
        uint256 _pool = balance();
        // 之前 = 当前合约的WETH余额
        uint256 _before = token.balanceOf(address(this));
        // 将调用者的WETH发送到当前合约
        token.safeTransferFrom(msg.sender, address(this), _amount);
        // 之后 = 当前合约的WETH余额
        uint256 _after = token.balanceOf(address(this));
        // 数量 = 之后 - 之前 (额外检查通缩标记)
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        uint256 shares = 0;
        // 计算份额
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            // 份额 = 存款数额 * 总量 / 池子数量
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        // 为调用者铸造份额
        _mint(msg.sender, shares);
    }

    /**
     * @dev ETH存款方法
     * @param _amount 存款数额
     * @notice 当前合约在WETH的余额发送到当前合约,并铸造份额币
     */
    function depositETH() public payable {
        // 池子数量 = 当前合约和控制器合约在WETH的余额
        uint256 _pool = balance();
        // 之前 = 当前合约的WETH余额
        uint256 _before = token.balanceOf(address(this));
        // 数额 = 发送的ETH数额
        uint256 _amount = msg.value;
        // 调用WETH的存款方法将数额存入WETH,并铸造WETH
        WETH(address(token)).deposit.value(_amount)();
        // 之后 = 当前合约的WETH余额
        uint256 _after = token.balanceOf(address(this));
        // 数量 = 之后 - 之前 (额外检查通缩标记)
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        uint256 shares = 0;
        // 计算份额
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            // 份额 = 存款数额 * 总量 / 池子数量
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        // 为调用者铸造份额
        _mint(msg.sender, shares);
    }

    /**
     * @dev 全部提款方法
     * @notice 将调用者的全部份额发送到提款方法
     */
    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    /**
     * @dev ETH全部提款方法
     * @notice 将调用者的全部份额发送到ETH提款方法
     */
    function withdrawAllETH() external {
        withdrawETH(balanceOf(msg.sender));
    }

    /**
     * @dev 收获方法
     * @notice 只能由控制器合约调用, 将收获Token发送到控制器合约
     */
    // 用于将超出债务限额的所有借入准备金交换以清算为“代币”
    // Used to swap any borrowed reserve over the debt limit to liquidate to 'token'
    function harvest(address reserve, uint256 amount) external {
        require(msg.sender == controller, "!controller");
        require(reserve != address(token), "token");
        IERC20(reserve).safeTransfer(controller, amount);
    }

    /**
     * @dev 提款方法
     * @param _shares 份额数量
     * @notice 
     */
    // 无需重新实施余额以降低费用并加快交换速度
    // No rebalance implementation for lower fees and faster swaps
    function withdraw(uint256 _shares) public {
        // 当前合约和控制器合约在WETH的余额 * 份额 / 总量
        uint256 r = (balance().mul(_shares)).div(totalSupply());
        // 销毁份额
        _burn(msg.sender, _shares);

        // 检查余额
        // Check balance
        // 当前合约在WETH的余额
        uint256 b = token.balanceOf(address(this));
        // 如果余额 < 份额对应的余额
        if (b < r) {
            // 提款数额 = 份额对应的余额 - 余额
            uint256 _withdraw = r.sub(b);
            // 控制器的提款方法将WETH提款到当前合约
            Controller(controller).withdraw(address(token), _withdraw);
            // 之后 = 当前合约的WETH余额
            uint256 _after = token.balanceOf(address(this));
            // 区别 = 之后 - 份额对应的余额
            uint256 _diff = _after.sub(b);
            // 如果区别 < 提款数额
            if (_diff < _withdraw) {
                // 份额对应的余额 = 余额 + 区别
                r = b.add(_diff);
            }
        }

        // 将数量为份额对应的余额的WETH发送到调用者账户
        token.safeTransfer(msg.sender, r);
    }

    /**
     * @dev ETH提款方法
     * @param _shares 份额数量
     * @notice 
     */
    // No rebalance implementation for lower fees and faster swaps
    function withdrawETH(uint256 _shares) public {
        // 当前合约和控制器合约在WETH的余额 * 份额 / 总量
        uint256 r = (balance().mul(_shares)).div(totalSupply());
        // 销毁份额
        _burn(msg.sender, _shares);

        // 检查余额
        // Check balance
        // 当前合约在WETH的余额
        uint256 b = token.balanceOf(address(this));
        // 如果余额 < 份额对应的余额
        if (b < r) {
            // 提款数额 = 份额对应的余额 - 余额
            uint256 _withdraw = r.sub(b);
            // 控制器的提款方法将WETH提款到当前合约
            Controller(controller).withdraw(address(token), _withdraw);
            // 之后 = 当前合约的WETH余额
            uint256 _after = token.balanceOf(address(this));
            // 区别 = 之后 - 份额对应的余额
            uint256 _diff = _after.sub(b);
            // 如果区别 < 提款数额
            if (_diff < _withdraw) {
                // 份额对应的余额 = 余额 + 区别
                r = b.add(_diff);
            }
        }

        // 调用WETH合约的取款方法,取出ETH
        WETH(address(token)).withdraw(r);
        // 将数量为份额对应的余额的ETH发送到调用者账户
        address(msg.sender).transfer(r);
    }

    function getPricePerFullShare() public view returns (uint256) {
        return balance().mul(1e18).div(totalSupply());
    }

    function() external payable {
        if (msg.sender != address(token)) {
            depositETH();
        }
    }
}
