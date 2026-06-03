// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// 发放利息的 ERC20
contract RewardERC20 is ERC20 {
    constructor() ERC20("RewardERC20", "RewardERC20") {}
}
