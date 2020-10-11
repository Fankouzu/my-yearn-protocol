/**
 *Submitted for verification at Etherscan.io on 2020-08-06
*/

pragma solidity ^0.5.16;

import "./common.sol";

// TUSD保险库合约 0x37d19d1c4E1fa9DC47bD1eA12f742a0887eDa74a
contract yVault is ERC20, ERC20Detailed {
  using SafeERC20 for IERC20;
  using Address for address;
  using SafeMath for uint256;

  IERC20 public token;
  
  uint public min = 9500;
  uint public constant max = 10000;
  
  address public governance;
  address public controller;

  constructor (address _token, address _controller) public ERC20Detailed(
      string(abi.encodePacked("yearn ", ERC20Detailed(_token).name())),
      string(abi.encodePacked("y", ERC20Detailed(_token).symbol())),
      ERC20Detailed(_token).decimals()
  ) {
      token = IERC20(_token);
      governance = msg.sender;
      controller = _controller;
  }
  
  function balance() public view returns (uint) {
      return token.balanceOf(address(this))
             .add(Controller(controller).balanceOf(address(token)));
  }
  
  function setMin(uint _min) external {
      require(msg.sender == governance, "!governance");
      min = _min;
  }
  
  function setGovernance(address _governance) public {
      require(msg.sender == governance, "!governance");
      governance = _governance;
  }
  
  function setController(address _controller) public {
      require(msg.sender == governance, "!governance");
      controller = _controller;
  }
  
  // Custom logic in here for how much the vault allows to be borrowed
  // Sets minimum required on-hand to keep small withdrawals cheap
  function available() public view returns (uint) {
      return token.balanceOf(address(this)).mul(min).div(max);
  }
  
  function earn() public {
      uint _bal = available();
      token.safeTransfer(controller, _bal);
      Controller(controller).earn(address(token), _bal);
  }
  
  function depositAll() external {
      deposit(token.balanceOf(msg.sender));
  }

  function deposit(uint _amount) public {
      uint _pool = balance();
      uint _before = token.balanceOf(address(this));
      token.safeTransferFrom(msg.sender, address(this), _amount);
      uint _after = token.balanceOf(address(this));
      _amount = _after.sub(_before); // Additional check for deflationary tokens
      uint shares = 0;
      if (totalSupply() == 0) {
        shares = _amount;
      } else {
        shares = (_amount.mul(totalSupply())).div(_pool);
      }
      _mint(msg.sender, shares);
  }
  
  function withdrawAll() external {
      withdraw(balanceOf(msg.sender));
  }

  // No rebalance implementation for lower fees and faster swaps
  function withdraw(uint _shares) public {
      uint r = (balance().mul(_shares)).div(totalSupply());
      _burn(msg.sender, _shares);

      // Check balance
      uint b = token.balanceOf(address(this));
      if (b < r) {
          uint _withdraw = r.sub(b);
          Controller(controller).withdraw(address(token), _withdraw);
          uint _after = token.balanceOf(address(this));
          uint _diff = _after.sub(b);
          if (_diff < _withdraw) {
              r = b.add(_diff);
          }
      }
      
      token.safeTransfer(msg.sender, r);
  }

  function getPricePerFullShare() public view returns (uint) {
    return balance().mul(1e18).div(totalSupply());
  }
}