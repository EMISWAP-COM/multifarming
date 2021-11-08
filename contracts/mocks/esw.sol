// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockESW is ERC20 {
    uint256 private constant _INITIAL_SUPPLY = 10_000_000_000 * (10**18);

    constructor() public ERC20("ESW token", "ESW") {
        _mint(msg.sender, _INITIAL_SUPPLY);
    }
}
