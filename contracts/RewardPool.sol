// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./IRewardDistributionRecipient.sol";
import "./LPTokenWrapper.sol";

//import "hardhat/console.sol";

contract RewardPool is LPTokenWrapper, IRewardDistributionRecipient, ReentrancyGuard {
    uint256 public totalStakeLimit; // max value in USD coin (last in route), rememeber decimals!
    address[] public route;
    uint8 marketID;
    uint8 id;

    IERC20 public rewardToken;
    uint256 public minPriceAmount;
    uint256 public constant DURATION = 90 days;

    uint256 public periodFinish = 0;
    uint256 public periodStop = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public tokenMode; // 0 = simple ERC20 token, 1 = Emiswap LP-token
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    /**
     * @dev seting main farming config
     * @param _rewardToken reward token, staketoken (first stake token) is the same
     * @param _rewardAdmin reward administrator
     */

    constructor(
        address _rewardToken,
        address _rewardAdmin,
        address _emiFactory,
        address _stableCoin
    ) public {
        rewardToken = IERC20(_rewardToken);
        stakeToken = _rewardToken;
        setRewardDistribution(_rewardAdmin);
        stakeTokens.push(_rewardToken);
        emiFactory = IEmiswapRegistry(_emiFactory);
        stableCoin = _stableCoin;
        //console.log("1 stakeTokens %s", stakeToken);
        //console.log("1 stakeTokens.length %s", stakeTokens.length);
        //minPriceAmount = _minPriceAmount;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /* function setEmiPriceData(address _emiFactory, address[] memory _route) public onlyOwner {
        if (emiFactory != _emiFactory) {
            emiFactory = _emiFactory;
        }
        if (route.length > 0) {
            delete route;
        }
        for (uint256 index = 0; index < _route.length; index++) {
            route.push(_route[index]);
        }
    } */

    function setMinPriceAmount(uint256 newMinPriceAmount) public onlyOwner {
        minPriceAmount = newMinPriceAmount;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOfStakeToken(account).mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(
                rewards[account]
            );
    }

    /**
     * @dev stake function, starts farming on stale, user stake two tokens: "Emiswap LP" + "ESW"
     * @param lp address of Emiswap LP token
     * @param lpAmount amount of Emiswap LP tokens
     * @param amount amount of ESW tokens
     */

    function stake(
        address lp,
        uint256 lpAmount,
        uint256 amount
    ) public override nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        require(block.timestamp <= periodFinish && block.timestamp <= periodStop, "Cannot stake yet");
        super.stake(lp, lpAmount, amount);
        //(, uint256 totalStake) = getStakedValuesinUSD(msg.sender);
        //console.log("stake: totalStakeLimit %s totalStake %s amount %s", totalStakeLimit, totalStake, amount);
        emit Staked(msg.sender, amount);
    }

    // TODO: т.к. общая ставка это ESW и множество LP то для простоты вывод делается только польностью
    function withdrawAll() internal nonReentrant updateReward(msg.sender) {
        require(balanceOfStakeToken(msg.sender) > 0, "no balance");
        super.withdraw();
        emit Withdrawn(msg.sender, balanceOfStakeToken(msg.sender));
    }

    function exit() external {
        withdrawAll();
        getReward();
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        /* uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        } */
    }

    // use it after create and approve of reward token

    function notifyRewardAmount(uint256 reward) external override onlyRewardDistribution updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(DURATION);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(DURATION);
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(DURATION);
        periodStop = periodFinish;
        rewardToken.safeTransferFrom(msg.sender, address(this), reward);
        emit RewardAdded(reward);
    }

    function addRoutes(address[] memory _route) public override onlyOwner {
        super.addRoutes(_route);
    }

    function activationRoute(address[] memory _route, bool _isActive) public override onlyOwner {
        super.activationRoute(_route, _isActive);
    }

    function setPeriodStop(uint256 _periodStop) external onlyRewardDistribution {
        require(periodStop <= periodFinish, "Incorrect stop");
        periodStop = _periodStop;
    }

    function getStakedValuesinUSD(address wallet) public view returns (uint256 senderStake, uint256 totalStake) {
        uint256 price = getAmountOut(minPriceAmount, route); /*1e18 default value of ESW, first of route always ESW*/
        // simple ERC-20
        if (tokenMode == 0) {
            senderStake = balanceOfStakeToken(wallet).mul(price).div(minPriceAmount);
            totalStake = totalSupply().mul(price).div(minPriceAmount);
        }
        if (tokenMode == 1) {
            /*uint256 lpFractionWallet = balanceOf(wallet).mul(1e18).div(stakeToken.totalSupply());
            uint256 lpFractionTotal = totalSupply().mul(1e18).div(stakeToken.totalSupply());
            uint256 ESWreserveWallet = IEmiswap(address(stakeToken)).getBalanceForAddition( IERC20(route[0]) ).mul(2).mul(lpFractionWallet).div(1e18);
            uint256 ESWreserveTotal = IEmiswap(address(stakeToken)).getBalanceForAddition( IERC20(route[0]) ).mul(2).mul(lpFractionTotal).div(1e18);
            senderStake = ESWreserveWallet.mul(price).div(minPriceAmount);
            totalStake = ESWreserveTotal.mul(price).div(minPriceAmount);*/

            senderStake = IEmiswap(stakeToken)
                .getBalanceForAddition(IERC20(route[0]))
                .mul(2)
                .mul(balanceOfStakeToken(wallet).mul(1e18).div(IERC20(stakeToken).totalSupply()))
                .div(1e18)
                .mul(price)
                .div(minPriceAmount);
            totalStake = IEmiswap(stakeToken)
                .getBalanceForAddition(IERC20(route[0]))
                .mul(2)
                .mul(totalSupply().mul(1e18).div(IERC20(stakeToken).totalSupply()))
                .div(1e18)
                .mul(price)
                .div(minPriceAmount);
        }
    }

    function getAmountOut(uint256 amountIn, address[] memory path) public view returns (uint256) {
        return EmiswapLib.getAmountsOut(address(emiFactory), amountIn, path)[path.length - 1];
    }

    // ------------------------------------------------------------------------
    //
    // ------------------------------------------------------------------------
    /**
     * @dev Owner can transfer out any accidentally sent ERC20 tokens
     * @param tokenAddress Address of ERC-20 token to transfer
     * @param beneficiary Address to transfer to
     * @param amount of tokens to transfer
     */
    function transferAnyERC20Token(
        address tokenAddress,
        address beneficiary,
        uint256 amount
    ) public onlyOwner returns (bool success) {
        require(tokenAddress != address(0), "address 0!");
        require(tokenAddress != address(stakeToken), "not staketoken");

        return IERC20(tokenAddress).transfer(beneficiary, amount);
    }
}
