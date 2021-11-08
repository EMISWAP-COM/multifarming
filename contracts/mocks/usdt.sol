// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDT is ERC20 {
    uint256 private constant _INITIAL_SUPPLY = 10000000000 * (10**6);

    constructor() public ERC20("USDT token", "USDT") {
        _mint(msg.sender, _INITIAL_SUPPLY);
        _setupDecimals(6);
    }
}
