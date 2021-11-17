// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

//import "hardhat/console.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./interfaces/IEmiswap.sol";
import "./libraries/EmiswapLib.sol";

interface IERC20Extented is IERC20Upgradeable {
    function decimals() external view returns (uint8);
}

contract LPTokenWrapper {
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // minimal time to be passed from wallet first stake to allow exit
    uint256 public exitTimeOut;

    mapping(address => uint256) public exitLimits;

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

    event Staked(address indexed user, address lp, uint256 lpAmount, uint256 amount);

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

    /**
     * @dev get route info
     * @param _route input route
     * @return routeRes stored route if found
     * @return isActiveRes is active flag
     */

    function getRoute(address[] memory _route) public view returns (address[] memory routeRes, bool isActiveRes) {
        for (uint256 index = 0; index < routeToStable.length; index++) {
            if (keccak256(abi.encodePacked(routeToStable[index].route)) == keccak256(abi.encodePacked(_route))) {
                routeRes = routeToStable[index].route;
                isActiveRes = routeToStable[index].isActive;
            }
        }
    }

    /**
     * @dev get route info by routeID
     * @param routeID input route
     * @return routeRes stored route if found
     * @return isActiveRes is active flag
     */

    function getRouteInfo(uint256 routeID) public view returns (address[] memory routeRes, bool isActiveRes) {
        routeRes = routeToStable[routeID].route;
        isActiveRes = routeToStable[routeID].isActive;
    }

    /**
     * @dev stake two tokens: lp and stake token (esw)
     * @param lp lp token address
     * @param lpAmount lp token amount
     * @param amountMax stake token maximum amount to take in
     */

    function stake(
        address lp,
        uint256 lpAmount,
        uint256 amountMax
    ) public virtual {
        require(emiFactory.isPool(lp), "token incorrect or not LP");

        // calc needful stake token amount
        uint256 stakeTokenAmount = getStakeValuebyLP(lp, lpAmount);
        require(stakeTokenAmount > 0 && stakeTokenAmount <= amountMax, "not enough stake token amount");

        IERC20Upgradeable(stakeToken).safeTransferFrom(msg.sender, address(this), stakeTokenAmount);
        IERC20Upgradeable(lp).safeTransferFrom(msg.sender, address(this), lpAmount);

        // incease total supply in stake token
        _totalSupply = _totalSupply.add(stakeTokenAmount);

        // set balances
        _balances[msg.sender][stakeToken] = _balances[msg.sender][stakeToken].add(stakeTokenAmount);
        _balances[msg.sender][lp] = _balances[msg.sender][lp].add(lpAmount);
        // save lp token stake, and also stakeToken by default
        if (tokensIndex[lp] == 0) {
            stakeTokens.push(lp);
            tokensIndex[lp] = stakeTokens.length;
        }
        // if first stake, save exit timeout
        if (exitLimits[msg.sender] == 0) {
            exitLimits[msg.sender] = block.timestamp + exitTimeOut;
        }
        emit Staked(msg.sender, lp, lpAmount, stakeTokenAmount);
    }

    /**
     * @dev calcilate stake value from LP token amount
     * @param _lp LP token address
     * @param _lpAmount LP token amount
     * @return  stakeValue LP amount value nominated in stake tokens
     */

    function getStakeValuebyLP(address _lp, uint256 _lpAmount) public view returns (uint256 stakeValue) {
        uint256 lpInStable = getLPValueInStable(_lp, _lpAmount);
        uint256 stakeTokenPrice = getTokenPrice(stakeToken);
        uint256 oneStakeTokenValue = 10**uint256(IERC20Extented(stakeToken).decimals());
        stakeValue = oneStakeTokenValue.mul(lpInStable).div(stakeTokenPrice);
    }

    /**
     * @dev calcilate LP value from stake token amount, function is reverse to getStakeValuebyLP
     * @param _lp LP token address
     * @param _amount stake token amount
     * @return lpValue stake amount value nominated in LP tokens
     */

    function getLPValuebyStake(address _lp, uint256 _amount) public view returns (uint256 lpValue) {
        uint256 oneLpAmount = 10**uint256(IERC20Extented(_lp).decimals());
        uint256 oneStakeToken = 10**uint256(IERC20Extented(stakeToken).decimals());
        uint256 oneLPInStable = getLPValueInStable(_lp, oneLpAmount);
        uint256 stakeTokenValueinStable = _amount.mul(getTokenPrice(stakeToken)).div(oneStakeToken);
        lpValue = oneLpAmount.mul(stakeTokenValueinStable).div(oneLPInStable);
    }

    /**
     * @dev get LP value in stable coins
     * @param _lp lp address
     * @param _lpAmount lp tokens amount
     */

    function getLPValueInStable(address _lp, uint256 _lpAmount) public view returns (uint256 lpValueInStable) {
        for (uint256 i = 0; i <= 1; i++) {
            address componentToken = address(IEmiswap(_lp).tokens(i));
            uint256 oneTokenValue = 10**uint256(IERC20Extented(componentToken).decimals());
            uint256 tokenPrice = getTokenPrice(componentToken);
            uint256 tokensInLP = getTokenAmountinLP(_lp, _lpAmount, componentToken);
            // calc token value from one of parts and multiply 2
            lpValueInStable = tokensInLP.mul(tokenPrice).mul(2).div(oneTokenValue);
            if (lpValueInStable > 0) {
                break;
            }
        }
    }

    /**
     * @dev get token price using existing token routes
     * @param token address of token
     */
    function getTokenPrice(address token) public view returns (uint256 tokenPrice) {
        require(IERC20Extented(token).decimals() > 0, "token must have decimals");
        uint256 oneTokenValue = 10**uint256(IERC20Extented(token).decimals());

        // go throuout all path and find minimal token price > 0
        for (uint256 i = 0; i < routeToStable.length; i++) {
            if (routeToStable[i].isActive) {
                // route must not contain token
                bool skipRoute;
                for (uint256 k = 0; k < routeToStable[i].route.length; k++) {
                    if (routeToStable[i].route[k] == token) {
                        skipRoute = true;
                        break;
                    }
                }
                if (skipRoute) {
                    break;
                }

                // prepare route to get price from token
                address[] memory route = new address[](routeToStable[i].route.length + 1);
                route[0] = token;
                for (uint256 j = 1; j < route.length; j++) {
                    route[j] = routeToStable[i].route[j - 1];
                }

                // get price by route
                uint256 _price = EmiswapLib.getAmountsOut(address(emiFactory), oneTokenValue, route)[route.length - 1];

                // choose minimum not zero price
                if (tokenPrice == 0) {
                    tokenPrice = _price;
                } else {
                    if (_price > 0 && _price < tokenPrice) {
                        tokenPrice = _price;
                    }
                }
            }
        }
    }

    /**
     * @dev get component token amount in passed amount of LP token
     * @param lp addres of LP token
     * @param lpAmount amount of LP token
     * @param component component token address (of LP)
     */
    function getTokenAmountinLP(
        address lp,
        uint256 lpAmount,
        address component
    ) public view returns (uint256 tokenAmount) {
        tokenAmount = IERC20(component).balanceOf(lp).mul(lpAmount).div(IERC20(lp).totalSupply());
    }

    /**
     * @dev get staked tokens by wallet
     * @param wallet address
     * @return tokens list of staked tokens
     */

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

    /**
     * @dev withdraw all staked tokens at once and reset exit date limits
     */

    function withdraw() internal virtual {
        require(block.timestamp >= exitLimits[msg.sender], "withdraw blocked");
        uint256 amount = _balances[msg.sender][stakeToken];

        // set balances
        _totalSupply = _totalSupply.sub(amount);

        for (uint256 index = 0; index < stakeTokens.length; index++) {
            IERC20Upgradeable(stakeTokens[index]).safeTransfer(msg.sender, _balances[msg.sender][stakeTokens[index]]);
            _balances[msg.sender][stakeTokens[index]] = 0;
        }

        // reset exit date limits
        exitLimits[msg.sender] = 0;
    }
}
