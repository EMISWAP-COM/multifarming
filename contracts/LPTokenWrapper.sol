// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "hardhat/console.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IEmiswap.sol";

contract IERC20Extented is IERC20 {
    function decimals() public view returns (uint8);
}

contract LPTokenWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Stable coin
    address public stableCoin;

    // path to stable on Emiswap dex
    struct path {
        address[] route;
        bool isActive;
    }

    // Routs to stable coin
    path[] public routeToStable;

    // save hash of path to check unique
    mapping(bytes32 => bool) public availableRoutes;

    // EmiFactory
    IEmiswapRegistry public emiFactory;

    // is the main token (ESW)
    address public stakeToken;

    // main token (ESW) supply
    uint256 private _totalSupply;

    // wallet -> lp -> amount
    mapping(address => mapping(address => uint256)) private _balances;

    // 0 means the token address is not in the array
    mapping(address => uint256) internal tokensIndex;
    // used stake tokens
    address[] public stakeTokens;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOfStakeToken(address account) public view returns (uint256) {
        return _balances[account][stakeToken];
    }

    function balanceOfLPToken(address account, address lp) public view returns (uint256) {
        return _balances[account][lp];
    }

    /**
     * @dev admin function to setup price routes to the "stableCoin"
     * @param route - route must ends with "stableCoin", and can consist only of 1 element - "stableCoin"
     */

    function addRoutes(address[] memory route) public virtual {
        require(route.length > 0 && route[route.length - 1] == stableCoin, "set route to stable");
        require(!availableRoutes[keccak256(abi.encodePacked(route))], "route already added");
        availableRoutes[keccak256(abi.encodePacked(route))] = true;
        routeToStable.push(path(route, true));
    }

    /**
     * @dev activate/deactivate route
     * @param _route array of tokens
     * @param _isActive change to true/false enable/disable
     */

    function activationRoute(address[] memory _route, bool _isActive) public virtual {
        for (uint256 index = 0; index < routeToStable.length; index++) {
            if (
                keccak256(abi.encodePacked(routeToStable[index].route)) == keccak256(abi.encodePacked(_route)) &&
                routeToStable[index].isActive != _isActive
            ) {
                routeToStable[index].isActive = _isActive;
                return;
            }
        }
    }

    function getRoute(address[] memory _route) public view returns (address[] memory routeRes, bool isActiveRes) {
        for (uint256 index = 0; index < routeToStable.length; index++) {
            if (keccak256(abi.encodePacked(routeToStable[index].route)) == keccak256(abi.encodePacked(_route))) {
                routeRes = routeToStable[index].route;
                isActiveRes = routeToStable[index].isActive;
            }
        }
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
        require(emiFactory.isPool(lp), "token incorrect or not LP");
        // TODO: is LP token has price in USDT?        
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

    function getLPValue(address _lp, uint256 _lpAmount) public view returns (uint256 lpValue) {
        for (uint256 index = 0; index < 1; index++) {
            uint256 oneStableValue = 10**IERC20Extented(stableCoin).decimals();
            uint256 oneTokenValue = 10**IERC20Extented(IEmiswap(_lp).tokens(index)).decimals();
            uint256 tokenPrice = getTokenPrice(IEmiswap(_lp).tokens(index));
            uint256 tokensInLP = getTokenAmountinLP(_lp, _lpAmount);
            lpValue = 2 * (  tokensInLP * tokenPrice / oneTokenValue );
        } // TODO: make getTokenPrice, getTokensinLP
    }

    function getStakedTokens(address wallet) public view returns (address[] memory tokens) {
        if (wallet == address(0)) {
            return (stakeTokens);
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
            for (uint256 index = stakeTokens.length; index > 0; index--) {
                if (_balances[wallet][stakeTokens[index - 1]] > 0) {
                    _tokens[count - 1] = stakeTokens[index - 1];
                    count--;
                }
            }
            return (_tokens);
        }
    }

    function withdraw() public virtual {
        uint256 amount = _balances[msg.sender][stakeToken];

        // set balances
        _totalSupply = _totalSupply.sub(amount);

        for (uint256 index = 0; index < stakeTokens.length; index++) {
            IERC20(stakeTokens[index]).safeTransfer(msg.sender, _balances[msg.sender][stakeTokens[index]]);
            _balances[msg.sender][stakeTokens[index]] = 0;
        }
    }
}
