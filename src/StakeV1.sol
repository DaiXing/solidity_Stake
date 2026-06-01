// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

struct Pool {
    // 每个区块的奖励。
    uint256 rewardPerBlock;
}
contract StackV1 {
    using Strings for uint256;
    // 区块。开始位置。
    uint256 startBlock1;
    // 区块。结束位置。
    uint256 endBlock;
    // 每个区块的奖励。
    uint256 rewardPerBlock;
    // 添加1个池子。
    function addPool() public {}
}
