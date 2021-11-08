// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "hardhat/console.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LPTokenWrapper{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public stakeToken; // is the main token (ESW)

    uint256 private _totalSupply; // main token (ESW) supply
    //mapping(address => uint256) private _balances;

    // wallet -> lp -> amount
    mapping(address => mapping(address => uint256)) private _balances;

    // 0 means the token address is not in the array
    mapping (address => uint) internal tokensIndex;
    // used stake tokens
    address[] public stakeTokens;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    // deprecated
    function balanceOf(address account) public pure returns (uint256) {
        return 0;
    }

    function balanceOfStakeToken(address account) public view returns (uint256) {
        return _balances[account][stakeToken];
    }

    function balanceOfLPToken(address account, address lp) public view returns (uint256) {
        return _balances[account][lp];
    }

    /**
     * @dev stake two tokens: lp and stake token (esw)
     * @param lp lp token address
     * @param lpAmount lp token amount
     * @param amount stake token amount
     */

    function stake(
        address lp,
        uint256 lpAmount,
        uint256 amount
    ) public virtual {
        // get tokens
        IERC20(stakeToken).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(lp).safeTransferFrom(msg.sender, address(this), lpAmount);

        // incease total supply in stake token
        _totalSupply = _totalSupply.add(amount);

        // set balances
        _balances[msg.sender][stakeToken] = _balances[msg.sender][stakeToken].add(amount);
        _balances[msg.sender][lp] = _balances[msg.sender][lp].add(lpAmount);
        // save lp token stake, and also stakeToken by default        
        if (tokensIndex[lp] == 0) {
            stakeTokens.push(lp);
            tokensIndex[lp] = stakeTokens.length;
        }
    }

    function getStakedTokens(address wallet) public view returns(address[] memory tokens) {
        if (wallet == address(0)){
            console.log("0");
            return(stakeTokens);
        } else {
            // calc elems
            uint8 count;
            for (uint256 index = 0; index < stakeTokens.length; index++) {
                if (_balances[wallet][stakeTokens[index]] > 0) {
                    count++;
                }
            }
            // get token adresses
            address[] memory _tokens = new address[](count);
            for (uint256 index = stakeTokens.length; index > 0 ; index--) {
                if (_balances[wallet][stakeTokens[index-1]] > 0) {
                    _tokens[count-1] = stakeTokens[index-1];
                    count--;
                }
            }
            return(_tokens);
        }
    }

    function withdraw() public virtual{

        uint256 amount = _balances[msg.sender][stakeToken];
        
        // set balances
        _totalSupply = _totalSupply.sub(amount);

        for (uint256 index = 0; index < stakeTokens.length; index++) {
            IERC20(stakeTokens[index]).safeTransfer(msg.sender, _balances[msg.sender][stakeTokens[index]]);
            _balances[msg.sender][stakeTokens[index]] = 0;
        }
    }
}
