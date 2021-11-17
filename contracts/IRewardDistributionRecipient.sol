// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract IRewardDistributionRecipient is OwnableUpgradeable {
    address public rewardDistribution;

    function notifyRewardAmount(uint256 reward) external virtual;

    modifier onlyRewardDistribution() {
        require(_msgSender() == rewardDistribution, "Caller is not reward distribution");
        _;
    }

    function setRewardDistribution(address _rewardDistribution)
        public
        /* external */
        onlyOwner
    {
        rewardDistribution = _rewardDistribution;
    }
}
