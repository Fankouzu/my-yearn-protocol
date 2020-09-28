/**
 *Submitted for verification at Etherscan.io on 2020-09-01
*/

pragma solidity ^0.5.17;

import "./common.sol";

/* MakerDao interfaces */

interface GemLike {
    function approve(address, uint) external;
    function transfer(address, uint) external;
    function transferFrom(address, address, uint) external;
    function deposit() external payable;
    function withdraw(uint) external;
}

interface ManagerLike {
    function cdpCan(address, uint, address) external view returns (uint);
    function ilks(uint) external view returns (bytes32);
    function owns(uint) external view returns (address);
    function urns(uint) external view returns (address);
    function vat() external view returns (address);
    function open(bytes32, address) external returns (uint);
    function give(uint, address) external;
    function cdpAllow(uint, address, uint) external;
    function urnAllow(address, uint) external;
    function frob(uint, int, int) external;
    function flux(uint, address, uint) external;
    function move(uint, address, uint) external;
    function exit(address, uint, address, uint) external;
    function quit(uint, address) external;
    function enter(address, uint) external;
    function shift(uint, uint) external;
}

interface VatLike {
    function can(address, address) external view returns (uint);
    function ilks(bytes32) external view returns (uint, uint, uint, uint, uint);
    function dai(address) external view returns (uint);
    function urns(bytes32, address) external view returns (uint, uint);
    function frob(bytes32, address, address, address, int, int) external;
    function hope(address) external;
    function move(address, address, uint) external;
}

interface GemJoinLike {
    function dec() external returns (uint);
    function gem() external returns (GemLike);
    function join(address, uint) external payable;
    function exit(address, uint) external;
}

interface GNTJoinLike {
    function bags(address) external view returns (address);
    function make(address) external returns (address);
}

interface DaiJoinLike {
    function vat() external returns (VatLike);
    function dai() external returns (GemLike);
    function join(address, uint) external payable;
    function exit(address, uint) external;
}

interface HopeLike {
    function hope(address) external;
    function nope(address) external;
}

interface EndLike {
    function fix(bytes32) external view returns (uint);
    function cash(bytes32, uint) external;
    function free(bytes32) external;
    function pack(uint) external;
    function skim(bytes32, address) external;
}

interface JugLike {
    function drip(bytes32) external returns (uint);
}

interface PotLike {
    function pie(address) external view returns (uint);
    function drip() external returns (uint);
    function join(uint) external;
    function exit(uint) external;
}

interface SpotLike {
    function ilks(bytes32) external view returns (address, uint);
}

interface OSMedianizer {
    function read() external view returns (uint, bool);
    function foresight() external view returns (uint, bool);
}

interface Uni {
    function swapExactTokensForTokens(uint, uint, address[] calldata, address, uint) external;
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

// WETH策略合约 地址:0x932fc4fd0eEe66F22f1E23fBA74D7058391c0b15
contract StrategyMKRVaultDAIDelegate {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // WETH
    address constant public token = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    // WETH
    address constant public want = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    // WETH
    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    // Dai Stablecoin
    address constant public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    // Maker: CDP Manager 
    address public cdp_manager = address(0x5ef30b9986345249bc32d8928B7ee64DE9435E39);
    // Maker: MCD Vat
    address public vat = address(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
    // Maker: MCD Join ETH A
    address public mcd_join_eth_a = address(0x2F0b23f53734252Bda2277357e97e1517d6B042A);
    // Maker: MCD Join DAI
    address public mcd_join_dai = address(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
    // Maker: MCD Spot
    address public mcd_spot = address(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);
    // Maker: MCD Jug
    address public jug = address(0x19c0976f590D67707E62397C87829d896Dc0f1F1);

    // OSMedianizer
    address public eth_price_oracle = address(0xCF63089A8aD2a9D8BD6Bb8022f3190EB7e1eD0f1);
    // yearn Dai Stablecoin (yDAI)
    address constant public yVaultDAI = address(0xACd43E627e64355f1861cEC6d3a6688B31a6F952);
    
    // Uniswap V2: Router 2
    address constant public unirouter = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // 借入抵押率
    uint public c = 20000;
    // 提取抵押率
    uint public c_safe = 30000;
    uint constant public c_base = 10000;

    uint public performanceFee = 500;
    uint constant public performanceMax = 10000;

    uint public withdrawalFee = 50;
    uint constant public withdrawalMax = 10000;

    uint public strategistReward = 5000;
    uint constant public strategistRewardMax = 10000;

    bytes32 constant public ilk = "ETH-A";

    address public governance; // 0xfeb4acf3df3cdea7399794d0869ef76a6efaff52 
    address public controller; // 0x9e65ad11b299ca0abefc2799ddb6314ef2d91080
    address public strategist; // 0x2839df1f230deda9fddbf1bcb0d4eb1ee1f7b7d0
    address public harvester; // 0x2d407ddb06311396fe14d4b49da5f0471447d45c
    // 13972
    uint public cdpId;

    /**
     * @dev 构造函数
     * @param _controller 控制器合约地址
     */
    // 0x9e65ad11b299ca0abefc2799ddb6314ef2d91080
    constructor(address _controller) public {
        governance = msg.sender;
        strategist = msg.sender;
        harvester = msg.sender;
        controller = _controller;
        // 打开MakerDao的抵押债仓
        cdpId = ManagerLike(cdp_manager).open(ilk, address(this));
        _approveAll();
    }

    function getName() external pure returns (string memory) {
        return "StrategyMKRVaultDAIDelegate";
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
     * @dev 设置收获地址
     * @param _harvester 收获地址
     * @notice 只能由治理地址设置
     */
    function setHarvester(address _harvester) external {
        require(msg.sender == harvester || msg.sender == governance, "!allowed");
        harvester = _harvester;
    }

    /**
     * @dev 设置提款手续费
     * @param _withdrawalFee 提款手续费
     * @notice 只能由治理地址设置
     */
    function setWithdrawalFee(uint _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        withdrawalFee = _withdrawalFee;
    }

    /**
     * @dev 设置性能费
     * @param _performanceFee 性能费
     * @notice 只能由治理地址设置
     */
    function setPerformanceFee(uint _performanceFee) external {
        require(msg.sender == governance, "!governance");
        performanceFee = _performanceFee;
    }

    /**
     * @dev 设置策略奖励
     * @param _strategistReward 奖励
     * @notice 只能由治理地址设置
     */
    function setStrategistReward(uint _strategistReward) external {
        require(msg.sender == governance, "!governance");
        strategistReward = _strategistReward;
    }

    /**
     * @dev 设置借入抵押率
     * @param _c 借入抵押率
     * @notice 只能由治理地址设置
     */
    function setBorrowCollateralizationRatio(uint _c) external {
        require(msg.sender == governance, "!governance");
        c = _c;
    }

    /**
     * @dev 设置提取抵押率
     * @param _c_safe 提取抵押率
     * @notice 只能由治理地址设置
     */
    function setWithdrawCollateralizationRatio(uint _c_safe) external {
        require(msg.sender == governance, "!governance");
        c_safe = _c_safe;
    }

    /**
     * @dev 设置预言机地址
     * @param _oracle 预言机地址
     * @notice 只能由治理地址设置
     */
    function setOracle(address _oracle) external {
        require(msg.sender == governance, "!governance");
        eth_price_oracle = _oracle;
    }

    /**
     * @dev 设置MCD值
     * @param _manager 
     * @param _ethAdapter 
     * @param _daiAdapter 
     * @param _spot 
     * @param _jug 
     * @notice 可选,只能由治理地址设置
     */
    // optional
    function setMCDValue(
        address _manager,
        address _ethAdapter,
        address _daiAdapter,
        address _spot,
        address _jug
    ) external {
        require(msg.sender == governance, "!governance");
        cdp_manager = _manager;
        vat = ManagerLike(_manager).vat();
        mcd_join_eth_a = _ethAdapter;
        mcd_join_dai = _daiAdapter;
        mcd_spot = _spot;
        jug = _jug;
    }

    /**
     * @dev 全部批准
     */
    function _approveAll() internal {
        // 批准WETH到Maker: MCD Join ETH A
        IERC20(token).approve(mcd_join_eth_a, uint(-1));
        // 批准DAI到Maker: MCD Join DAI
        IERC20(dai).approve(mcd_join_dai, uint(-1));
        // 批准DAI到yearn Dai Stablecoin (yDAI)
        IERC20(dai).approve(yVaultDAI, uint(-1));
        // 批准DAI到Uniswap V2: Router 2
        IERC20(dai).approve(unirouter, uint(-1));
    }

    /**
     * @dev 存款方法
     * @notice 将合约中的WETH生成DAI,发送给yVaultDAI
     */
    function deposit() public {
        // WETH余额 = 当前合约在WETH合约中的余额
        uint _token = IERC20(token).balanceOf(address(this));
        // 如果WETH余额 > 0
        if (_token > 0) {
            // ETH价格预言
            uint p = _getPrice();
            // _draw数额 = WETH余额 * ETH价格 * 10000 / 20000 / 1e18
            uint _draw = _token.mul(p).mul(c_base).div(c).div(1e18);
            // 检查债务上限
            // approve adapter to use token amount
            require(_checkDebtCeiling(_draw), "debt ceiling is reached!");
            // 锁定WETH生成DAI
            _lockWETHAndDrawDAI(_token, _draw);
        }
        // 向yearn Dai Stablecoin (yDAI)存款全部DAI
        // approve yVaultDAI use DAI
        yVault(yVaultDAI).depositAll();
    }

    /**
     * @dev 获取ETH价格
     * @notice 从预言机获取ETH价格
     */
    function _getPrice() internal view returns (uint p) {
        (uint _read,) = OSMedianizer(eth_price_oracle).read();
        (uint _foresight,) = OSMedianizer(eth_price_oracle).foresight();
        p = _foresight < _read ? _foresight : _read;
    }

    /**
     * @dev 检查债务上限
     */
    function _checkDebtCeiling(uint _amt) internal view returns (bool) {
        // MakerDao的债务上限
        (,,,uint _line,) = VatLike(vat).ilks(ilk);
        // 当前债务加上amt
        uint _debt = getTotalDebtAmount().add(_amt);
        // 债务上限小于当前债务+amt返回错误
        if (_line.div(1e27) < _debt) { return false; }
        return true;
    }

    /**
     * @dev 锁定WETH生成DAI
     * @param wad 当前合约在WETH合约中的余额
     * @param wadD 生成DAI的数量
     */
    function _lockWETHAndDrawDAI(uint wad, uint wadD) internal {
        // 0x806EF2C349e92C5D787C4cad15ACaBdf1a4644EB UrnHandler
        address urn = ManagerLike(cdp_manager).urns(cdpId);

        // GemJoinLike(mcd_join_eth_a).gem().approve(mcd_join_eth_a, wad);
        // 将vat移动到UrnHandler,销毁当前合约的DAI
        GemJoinLike(mcd_join_eth_a).join(urn, wad);
        // 对cdp进行跳转，使生成的DAI或抵押品在cdp缸地址中释放
        // Frob the cdp keeping the generated DAI or collateral freed in the cdp urn address.
        ManagerLike(cdp_manager).frob(cdpId, toInt(wad), _getDrawDart(urn, wadD));
        // 将一堆DAI从cdp地址传输到dst地址
        // Transfer wad amount of DAI from the cdp address to a dst address.
        ManagerLike(cdp_manager).move(cdpId, address(this), wadD.mul(1e27));
        // 
        if (VatLike(vat).can(address(this), address(mcd_join_dai)) == 0) {
            // VatLike(vat).can[msg.sender][mcd_join_dai] = 1
            VatLike(vat).hope(mcd_join_dai);
        }
        // 将vat从当前合约移动到mcd_join_dai,为当前合约铸造DAI
        DaiJoinLike(mcd_join_dai).exit(address(this), wadD);
    }

    /**
     * @dev 锁定WETH生成DAI
     * @param urn 当前合约在WETH合约中的余额
     * @param wad 生成DAI的数量
     */
    function _getDrawDart(address urn, uint wad) internal returns (int dart) {
        uint rate = JugLike(jug).drip(ilk);
        uint _dai = VatLike(vat).dai(urn);

        // 如果增值税余额中已经有足够的DAI，只需退出即可，无需增加更多债务
        // If there was already enough DAI in the vat balance, just exits it without adding more debt
        if (_dai < wad.mul(1e27)) {
            dart = toInt(wad.mul(1e27).sub(_dai).div(rate));
            dart = uint(dart).mul(rate) < wad.mul(1e27) ? dart + 1 : dart;
        }
    }

    function toInt(uint x) internal pure returns (int y) {
        y = int(x);
        require(y >= 0, "int-overflow");
    }

    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        require(dai != address(_asset), "dai");
        require(yVaultDAI != address(_asset), "ydai");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint _amount) external {
        require(msg.sender == controller, "!controller");
        uint _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }

        uint _fee = _amount.mul(withdrawalFee).div(withdrawalMax);

        IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
        address _vault = Controller(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds

        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
    }

    function _withdrawSome(uint256 _amount) internal returns (uint) {
        if (getTotalDebtAmount() != 0 && 
            getmVaultRatio(_amount) < c_safe.mul(1e2)) {
            uint p = _getPrice();
            _wipe(_withdrawDaiLeast(_amount.mul(p).div(1e18)));
        }
        
        _freeWETH(_amount);
        
        return _amount;
    }

    function _freeWETH(uint wad) internal {
        ManagerLike(cdp_manager).frob(cdpId, -toInt(wad), 0);
        ManagerLike(cdp_manager).flux(cdpId, address(this), wad);
        GemJoinLike(mcd_join_eth_a).exit(address(this), wad);
    }

    function _wipe(uint wad) internal {
        // wad in DAI
        address urn = ManagerLike(cdp_manager).urns(cdpId);

        DaiJoinLike(mcd_join_dai).join(urn, wad);
        ManagerLike(cdp_manager).frob(cdpId, 0, _getWipeDart(VatLike(vat).dai(urn), urn));
    }

    function _getWipeDart(
        uint _dai,
        address urn
    ) internal view returns (int dart) {
        (, uint rate,,,) = VatLike(vat).ilks(ilk);
        (, uint art) = VatLike(vat).urns(ilk, urn);

        dart = toInt(_dai / rate);
        dart = uint(dart) <= art ? - dart : - toInt(art);
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        _withdrawAll();

        _swap(IERC20(dai).balanceOf(address(this)));
        balance = IERC20(want).balanceOf(address(this));

        address _vault = Controller(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);
    }

    function _withdrawAll() internal {
        yVault(yVaultDAI).withdrawAll(); // get Dai
        _wipe(getTotalDebtAmount().add(1)); // in case of edge case
        _freeWETH(balanceOfmVault());
    }

    function balanceOf() public view returns (uint) {
        return balanceOfWant()
               .add(balanceOfmVault());
    }

    function balanceOfWant() public view returns (uint) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfmVault() public view returns (uint) {
        uint ink;
        address urnHandler = ManagerLike(cdp_manager).urns(cdpId);
        (ink,) = VatLike(vat).urns(ilk, urnHandler);
        return ink;
    }

    function harvest() public {
        require(msg.sender == strategist || msg.sender == harvester || msg.sender == governance, "!authorized");
        
        uint v = getUnderlyingDai();
        uint d = getTotalDebtAmount();
        require(v > d, "profit is not realized yet!");
        uint profit = v.sub(d);

        
        uint _before = IERC20(want).balanceOf(address(this));
        _swap(_withdrawDaiMost(profit));
        uint _after = IERC20(want).balanceOf(address(this));

        uint _want = _after.sub(_before);
        if (_want > 0) {
            uint _fee = _want.mul(performanceFee).div(performanceMax);
            uint _strategistReward = _fee.mul(strategistReward).div(strategistRewardMax);
            IERC20(want).safeTransfer(strategist, _strategistReward);
            IERC20(want).safeTransfer(Controller(controller).rewards(), _fee.sub(_strategistReward));
        }

        deposit();
    }
    
    function shouldDraw() external view returns (bool) {
        uint _safe = c.mul(1e2);
        uint _current = getmVaultRatio(0);
        if (_current > c_base.mul(c_safe).mul(1e2)) {
            _current = c_base.mul(c_safe).mul(1e2);
        }
        return (_current > _safe);
    }
    
    function drawAmount() public view returns (uint) {
        uint _safe = c.mul(1e2);
        uint _current = getmVaultRatio(0);
        if (_current > c_base.mul(c_safe).mul(1e2)) {
            _current = c_base.mul(c_safe).mul(1e2);
        }
        if (_current > _safe) {
            uint _eth = balanceOfmVault();
            uint _diff = _current.sub(_safe);
            uint _draw = _eth.mul(_diff).div(_safe).mul(c_base).mul(1e2).div(_current);
            return _draw.mul(_getPrice()).div(1e18);
        }
        return 0;
    }

    function draw() external {
        uint _drawD = drawAmount();
        if (_drawD > 0) {
            _lockWETHAndDrawDAI(0, _drawD);
            yVault(yVaultDAI).depositAll();
        }
    }
    
    function shouldRepay() external view returns (bool) {
        uint _safe = c.mul(1e2);
        uint _current = getmVaultRatio(0);
        _current = _current.mul(105).div(100); // 5% buffer to avoid deposit/rebalance loops
        return (_current < _safe);
    }
    
    function repayAmount() public view returns (uint) {
        uint _safe = c.mul(1e2);
        uint _current = getmVaultRatio(0);
        _current = _current.mul(105).div(100); // 5% buffer to avoid deposit/rebalance loops
        if (_current < _safe) {
            uint d = getTotalDebtAmount();
            uint diff = _safe.sub(_current);
            return d.mul(diff).div(_safe);
        }
        return 0;
    }
    
    function repay() external {
        uint free = repayAmount();
        if (free > 0) {
            _wipe(_withdrawDaiLeast(free));
        }
    }
    
    function forceRebalance(uint _amount) external {
        require(msg.sender == governance || msg.sender == strategist || msg.sender == harvester, "!authorized");
        _wipe(_withdrawDaiLeast(_amount));
    }

    function getTotalDebtAmount() public view returns (uint) {
        uint art;
        uint rate;
        address urnHandler = ManagerLike(cdp_manager).urns(cdpId);
        (,art) = VatLike(vat).urns(ilk, urnHandler);
        (,rate,,,) = VatLike(vat).ilks(ilk);
        return art.mul(rate).div(1e27);
    }

    function getmVaultRatio(uint amount) public view returns (uint) {
        uint spot; // ray
        uint liquidationRatio; // ray
        uint denominator = getTotalDebtAmount();

        if (denominator == 0) {
            return uint(-1);
        }

        (,,spot,,) = VatLike(vat).ilks(ilk);
        (,liquidationRatio) = SpotLike(mcd_spot).ilks(ilk);
        uint delayedCPrice = spot.mul(liquidationRatio).div(1e27); // ray

        uint _balance = balanceOfmVault();
        if (_balance < amount) {
            _balance = 0;
        } else {
            _balance = _balance.sub(amount);
        }

        uint numerator = _balance.mul(delayedCPrice).div(1e18); // ray
        return numerator.div(denominator).div(1e3);
    }

    function getUnderlyingDai() public view returns (uint) {
        return IERC20(yVaultDAI).balanceOf(address(this))
                .mul(yVault(yVaultDAI).getPricePerFullShare())
                .div(1e18);
    }

    function _withdrawDaiMost(uint _amount) internal returns (uint) {
        uint _shares = _amount
                        .mul(1e18)
                        .div(yVault(yVaultDAI).getPricePerFullShare());
        
        if (_shares > IERC20(yVaultDAI).balanceOf(address(this))) {
            _shares = IERC20(yVaultDAI).balanceOf(address(this));
        }

        uint _before = IERC20(dai).balanceOf(address(this));
        yVault(yVaultDAI).withdraw(_shares);
        uint _after = IERC20(dai).balanceOf(address(this));
        return _after.sub(_before);
    }

    function _withdrawDaiLeast(uint _amount) internal returns (uint) {
        uint _shares = _amount
                        .mul(1e18)
                        .div(yVault(yVaultDAI).getPricePerFullShare())
                        .mul(withdrawalMax)
                        .div(withdrawalMax.sub(withdrawalFee));

        if (_shares > IERC20(yVaultDAI).balanceOf(address(this))) {
            _shares = IERC20(yVaultDAI).balanceOf(address(this));
        }

        uint _before = IERC20(dai).balanceOf(address(this));
        yVault(yVaultDAI).withdraw(_shares);
        uint _after = IERC20(dai).balanceOf(address(this));
        return _after.sub(_before);
    }

    function _swap(uint _amountIn) internal {
        address[] memory path = new address[](2);
        path[0] = address(dai);
        path[1] = address(want);

        // approve unirouter to use dai
        Uni(unirouter).swapExactTokensForTokens(_amountIn, 0, path, address(this), now.add(1 days));
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