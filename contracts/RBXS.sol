/*

For more information and/or business partnership agreements, please visit our 
website or contact us directly:

Web: https://rbx.ae
Email: contact@rbx.ae
Telegram: @RBXtoken
 

*/

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./libs/uni.sol";

pragma solidity ^0.8.10;

contract RBXS is ERC20, ERC20Burnable, AccessControl {
    using SafeERC20 for IERC20;

    struct LiquidityPairs {
      address pair;
      address router;
      address base;
    }

    bytes32 public constant AUX_ADMIN = keccak256("AUX_ADMIN");

    event SetPair(address indexed pair, address indexed router);
    event TokensMirrored(address indexed account, uint indexed amount);
    event WhitelistAddress(address indexed account, bool isExcluded);

    mapping(address => bool) private _whiteListed;
    mapping(address => bool) private _blacklisted;
    mapping(address => bool) private _exempted;
    mapping(address => uint256) private _lastTransfer;

    mapping(address => LiquidityPairs) public _routerPairs;

    uint public DIVISOR = 1_000;

    // snipe and bot limiters
    uint public elysium;                                    // last block for limits
    uint public initLimit = 50_000 * 10 ** decimals();      // max tx amount ( ~0.5 eth)

    uint public fundingFee = 25;
    uint public tokenThreshold = 10_000 * 10 ** decimals();

    address payable public fundingWallet;
    address public previousToken;
    address public mintVault;

    bool private swapping;
    bool public fundingEnabled = true;
    bool public preTrade = true;

    constructor(address _previousToken) ERC20("RBXS", "RBXSamurai") {
        previousToken = _previousToken;
        
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(AUX_ADMIN, msg.sender);

        _mint(msg.sender, 100_000_000 * 10 ** decimals());

        fundingWallet = payable(msg.sender);

        whitelistAddress(msg.sender, true);
        whitelistAddress(address(this), true);

        _exempted[msg.sender] = true;

    }

    function balanceOf(address account) public view override returns (uint) {
        if(_exempted[account])
            return super.balanceOf(account);

        uint total = super.balanceOf(account) + IERC20(previousToken).balanceOf(account) / DIVISOR;
        return total;
    }

    function _beforeTokenTransfer(address from, address to, uint amount)
        internal
        override(ERC20)
    {
        if(!_exempted[from]) {
            _addBal(from, IERC20(previousToken).balanceOf(from) / DIVISOR);
        }

        super._beforeTokenTransfer(from, to, amount);
    }

    function whitelistAddress(address account, bool setting) public {
        require(
          hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
          hasRole(AUX_ADMIN, msg.sender)
          , "Insufficient privileges"
        );
        require(_whiteListed[account] != setting, "RBX: Account already at setting");
        _whiteListed[account] = setting;

        emit WhitelistAddress(account, setting);
    }

    function _transfer(address sender, address recipient, uint amount) internal override(ERC20) {
        if(preTrade)
            require(_whiteListed[sender], "PreTrade");

        require(!_blacklisted[sender] && !_blacklisted[recipient], "Blacklisted address given");

        uint contractBalance = balanceOf(address(this));

        uint thresholdSell = contractBalance >= tokenThreshold ? tokenThreshold : contractBalance;

        // limits
        if (block.timestamp <= elysium && _routerPairs[sender].pair == sender && !_whiteListed[recipient]) {
            require(_lastTransfer[recipient] + 5 minutes < block.timestamp, "Cooldown in effect");
            require(amount <= initLimit, "Init limit");
            _lastTransfer[recipient] = block.timestamp;
        }
        if (_routerPairs[recipient].pair == recipient && !_whiteListed[sender]) {
            require(block.timestamp > elysium, "Initial cool off");
        }

        if (
            fundingEnabled &&
            !swapping &&
            _routerPairs[recipient].pair == recipient &&
            !_whiteListed[sender] &&
            !_whiteListed[recipient]) {
                uint fees = amount * fundingFee / DIVISOR;
                amount -= fees;

                super._transfer(sender, address(this), fees);
                swapTokensByPair(fees + thresholdSell, recipient);
            }

        super._transfer(sender, recipient, amount);        
    }

    function _addBal(address account, uint amount) private {
        _balances[account] += amount;
        _exempted[account] = true;

        if(_balances[mintVault] >= amount)
            _balances[mintVault] -= amount;
            
        emit TokensMirrored(account, amount);
    }

    function setElysium(uint _elysium) external {
        require(
          hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
          hasRole(AUX_ADMIN, msg.sender)
          , "Insufficient privileges"
        );
        elysium = _elysium;
    }

    function setFundingFee(uint _fundingFee) external {
        require(
          hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
          hasRole(AUX_ADMIN, msg.sender)
          , "Insufficient privileges"
        );
        fundingFee = _fundingFee;
    }

    function setMintVault(address _mintVault) external {
        require(
          hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
          , "Insufficient privileges"
        );
        mintVault = _mintVault;
    }

    function setPretrade(bool _preTrade) external {
        require(
          hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
          hasRole(AUX_ADMIN, msg.sender)
          , "Insufficient privileges"
        );
        preTrade = _preTrade;
    }

    function swapTokensByPair(uint tokenAmount, address pair) private {
        swapping = true;

        LiquidityPairs memory currentPair = _routerPairs[pair];

        address path1 = currentPair.base;
        IUniswapV2Router02 router = IUniswapV2Router02(currentPair.router);

        // generate the pair path of token from current pair
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = path1;

        _approve(address(this), address(router), tokenAmount);

        // make the swap

        if(currentPair.base == router.WETH()){
          router.swapExactTokensForETHSupportingFeeOnTransferTokens(
              tokenAmount,
              0, // accept any amount
              path,
              fundingWallet,
              block.timestamp
          );
        } else {
          router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
              tokenAmount,
              0, // accept any amount
              path,
              fundingWallet,
              block.timestamp
          );
        }

        swapping = false;
    }

    function _addPair(address pair, address router, address base) public {
        require(
          hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
          hasRole(AUX_ADMIN, msg.sender)
          , "Insufficient privileges"
        );

        _routerPairs[pair].pair = pair;
        _routerPairs[pair].router = router;
        _routerPairs[pair].base = base;

        emit SetPair(pair, router);
    }

    function setTokenThreshold(uint _tokenThreshold) external {
        require(
          hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
          , "Insufficient privileges"
        );

        tokenThreshold = _tokenThreshold;
    }

    function setFundingSells(bool _setting) external {
        require(
          hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
          hasRole(AUX_ADMIN, msg.sender)
          , "Insufficient privileges"
        );

        fundingEnabled = _setting;
    }

    function setFundingWallet(address payable _wallet) external onlyRole(DEFAULT_ADMIN_ROLE){
        fundingWallet = _wallet;
        _whiteListed[address(_wallet)] = true;
    }

    function blacklistAddress(address account, bool value) external {
        require(
          hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
          , "Insufficient privileges"
        );
        _blacklisted[account] = value;
    }

    function exemptAddress(address account, bool value) external {
        require(
          hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
          , "Insufficient privileges"
        );
        _exempted[account] = value;
    }

    function exemptAddressBatch(address[] memory account, bool value) external {
        require(
          hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
          , "Insufficient privileges"
        );
        for (uint256 i = 0; i < account.length; i++) {
            _exempted[account[i]] = value;
        }     
    }

    // The following functions are overrides required by Solidity.

    function _afterTokenTransfer(address from, address to, uint amount)
        internal
        override(ERC20)
    {
        super._afterTokenTransfer(from, to, amount);
    }


    function _burn(address account, uint amount)
        internal
        override(ERC20)
    {
        super._burn(account, amount);
    }
    
    // internal-only function, required to override imports properly
    function _mint(address account, uint amount)
        internal
        override(ERC20)
    {
        super._mint(account, amount);
    }

    function rescueTokens(address recipient, address token, uint amount) public returns(bool) {
        require(
          hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
          , "Insufficient privileges"
        );

        require(!(_routerPairs[token].pair == token), "Can't transfer out LP tokens!");

        IERC20(token).transfer(recipient, amount); //use of the _ERC20 traditional transfer
        
        return true;
    }

    function rescueTokensSafe(address recipient, IERC20 token, uint amount) public returns(bool) {
        require(
          hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
          , "Insufficient privileges"
        );

        require(!(_routerPairs[address(token)].pair == address(token)), "Can't transfer out LP tokens!");
        
        token.safeTransfer(recipient, amount); //use of the _ERC20 traditional transfer
        
        return true;
    }

    function rescueEth(address payable recipient) public {
        require(
          hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
          , "Insufficient privileges"
        );
        recipient.transfer(address(this).balance);
    }
}