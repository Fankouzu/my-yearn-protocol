/**
 *Submitted for verification at Etherscan.io on 2020-07-26
 */

pragma solidity ^0.5.16;

import "./common.sol";

// USDC保险库合约 0x597aD1e0c13Bfe8025993D9e79C69E1c0233522e
contract yVault is ERC20, ERC20Detailed {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    // USD Coin
    IERC20 public token; // 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48

    // 最小值 / 最大值 = 95%
    uint256 public min = 9500;
    uint256 public constant max = 10000;

    // 治理地址
    address public governance; // 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52 proxy
    // 控制器合约
    address public controller; // 0x9e65ad11b299ca0abefc2799ddb6314ef2d91080

    /**
     * @dev 构造函数
     * @param _token 基础资产USDC
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

    /// @notice 当前合约在USDC的余额,加上控制器中当前合约的余额
    function balance() public view returns (uint256) {
        return
            token.balanceOf(address(this)).add(
                Controller(controller).balanceOf(address(token))
            );
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
     * @notice 当前合约在USDC的余额的95%
     */
    // 此处的自定义逻辑用于允许借用保险库的数量
    // 设置最低要求，以保持小额取款便宜
    // Custom logic in here for how much the vault allows to be borrowed
    // Sets minimum required on-hand to keep small withdrawals cheap
    function available() public view returns (uint256) {
        // 当前合约在USDC的余额 * 95%
        return token.balanceOf(address(this)).mul(min).div(max);
    }

    /**
     * @dev 赚钱方法
     * @notice 将空闲余额发送到控制器,再调用控制器的赚钱方法
     */
    function earn() public {
        // 空闲余额
        uint256 _bal = available();
        // 发送到控制器合约
        token.safeTransfer(controller, _bal);
        // 调用控制器合约的赚钱方法
        Controller(controller).earn(address(token), _bal);
    }

    /**
     * @dev 存款方法
     * @param _amount 存款数额
     * @notice 当前合约在USDC的余额发送到当前合约,并铸造份额币
     */
    function deposit(uint256 _amount) external {
        // 池子数量 = 当前合约和控制器合约在USDC的余额
        uint256 _pool = balance();
        // 将调用者的USDC发送到当前合约
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 shares = 0;
        // 计算份额
        if (_pool == 0) {
            shares = _amount;
        } else {
            // 份额 = 存款数额 * 总量 / 池子数量
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
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
    function withdraw(uint256 _shares) external {
        // 当前合约和控制器合约在USDC的余额 * 份额 / 总量
        uint256 r = (balance().mul(_shares)).div(totalSupply());
        // 销毁份额
        _burn(msg.sender, _shares);

        // 检查余额
        // Check balance
        // 当前合约在USDC的余额
        uint256 b = token.balanceOf(address(this));
        // 如果余额 < 份额对应的余额
        if (b < r) {
            // 提款数额 = 份额对应的余额 - 余额
            uint256 _withdraw = r.sub(b);
            // 控制器的提款方法将USDC提款到当前合约
            Controller(controller).withdraw(address(token), _withdraw);
            // 之后 = 当前合约的USDC余额
            uint256 _after = token.balanceOf(address(this));
            // 区别 = 之后 - 份额对应的余额
            uint256 _diff = _after.sub(b);
            // 如果区别 < 提款数额
            if (_diff < _withdraw) {
                // 份额对应的余额 = 余额 + 区别
                r = b.add(_diff);
            }
        }
        // 将数量为份额对应的余额的USDC发送到调用者账户
        token.safeTransfer(msg.sender, r);
    }

    function getPricePerFullShare() public view returns (uint256) {
        return balance().mul(1e18).div(totalSupply());
    }
}
