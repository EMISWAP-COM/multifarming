// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./IRewardDistributionRecipient.sol";
import "./LPTokenWrapper.sol";

contract RewardPoolMulti is LPTokenWrapper, IRewardDistributionRecipient, ReentrancyGuardUpgradeable {
    uint256 public totalStakeLimit; // max value in USD coin (last in route), rememeber decimals!
    address[] public route;

    IERC20Upgradeable public rewardToken;
    uint256 public duration;

    uint256 public periodFinish;
    uint256 public periodStop;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    /**
     * @dev seting main farming config
     * @param _rewardToken reward token, staketokeStakedss
     * @param _stableCoin stable token contract addres
     * @param _duration farming duration from start
     * @param _exitTimeOut exit and withdraw stakes allowed only when time passed from first wallet stake
     */

    function initialize(
        address _rewardToken,
        address _rewardAdmin,
        address _emiFactory,
        address _stableCoin,
        uint256 _duration,
        uint256 _exitTimeOut
    ) public virtual initializer {
        __Ownable_init();
        transferOwnership(_rewardAdmin);
        rewardDistribution = _rewardAdmin;

        rewardToken = IERC20Upgradeable(_rewardToken);
        stakeToken = _rewardToken;
        stakeTokens.push(_rewardToken);
        emiFactory = IEmiswapRegistry(_emiFactory);
        stableCoin = _stableCoin;
        duration = _duration;
        exitTimeOut = _exitTimeOut;
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
     * @param amount stake token maximum amount to take in
     */

    function stake(
        address lp,
        uint256 lpAmount,
        uint256 amount
    ) public override nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        require(block.timestamp <= periodFinish && block.timestamp <= periodStop, "Cannot stake yet");
        super.stake(lp, lpAmount, amount);
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

    function getReward() internal nonReentrant updateReward(msg.sender) {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    // use it after create and approve of reward token

    function notifyRewardAmount(uint256 reward) external override onlyRewardDistribution updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(duration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(duration);
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(duration);
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

    /**
     * @dev get staked values nominated in stable coin for the wallet and for all
     * @param wallet wallet for getting staked value
     * @return senderStake staked value for the wallet
     * @return totalStake staked value for all wallet on the contract
     */
    function getStakedValuesinUSD(address wallet) public view returns (uint256 senderStake, uint256 totalStake) {
        uint256 oneStakeToken = 10**uint256(IERC20Extented(stakeToken).decimals());
        senderStake = balanceOfStakeToken(wallet).mul(getTokenPrice(stakeToken)).div(oneStakeToken);
        totalStake = totalSupply().mul(getTokenPrice(stakeToken)).div(oneStakeToken);
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

        return IERC20Upgradeable(tokenAddress).transfer(beneficiary, amount);
    }
}
