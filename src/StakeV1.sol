// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

struct Pool {
    // 权重。
    uint256 weight;
}
contract StackV1 {
    using Strings for uint256;

    // 区块。开始位置。
    uint256 startBlock;
    // 区块。结束位置。
    uint256 endBlock;
    // 每个区块的奖励。
    uint256 rewardPerBlock;
    // 奖励合约。发奖励。 IERC20
    address rewardAddr;

    // 池子的ID
    uint256 poolId;
    // 池子。key= poolID
    mapping(uint256 => Pool) poolMap;

    // 初始化。
    function initialize(
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _rewardPerBlock,
        address _rewardAddr
    ) public {
        require(_startBlock > block.number, "_startBlock invalid");
        require(_endBlock < block.number, "_endBlock invalid");
        require(_rewardPerBlock > 0, "_rewardPerBlock invalid");
        require(_rewardAddr != address(0), "_rewardAddr invalid");

        startBlock = _startBlock;
        endBlock = _endBlock;
        rewardPerBlock = _rewardPerBlock;
        rewardAddr = _rewardAddr;

        // 判断合约有效
        IERC20 erc20 = IERC20(rewardAddr);
        uint256 supply = erc20.totalSupply();
        require(supply > 0, "reward not enough");
    }

    function setStartBlock(uint256 _startBlock) public {
        require(_startBlock >= block.number, "_startBlock invalid");
        require(_startBlock < endBlock, "_startBlock invalid");
        startBlock = _startBlock;
    }
    function setEndBlock(uint256 _endBlock) public {
        require(_endBlock >= block.number, "_endBlock invalid");
        require(_endBlock > startBlock, "_endBlock invalid");
        endBlock = _endBlock;
    }
    function setRewardPerBlock(uint256 _rewardPerBlock) public {
        require(_rewardPerBlock > 0, "_rewardPerBlock invalid");
        rewardPerBlock = _rewardPerBlock;
    }

    // 添加1个池子。
    function addPool(uint256 _weight) public {
        require(_weight > 0, "_weight invalid");

        poolId++;
        uint256 poolIdNew = poolId;
        poolMap[poolIdNew] = Pool({weight: _weight});
    }
}
