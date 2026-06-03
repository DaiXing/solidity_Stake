// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// 池子的本金的 ERC20
contract PoolERC20 is ERC20 {
    constructor() ERC20("PoolERC20", "PoolERC20") {}
}
