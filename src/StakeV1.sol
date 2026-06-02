// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

struct Pool {
    // 权重。
    uint256 weight;
    // token合约地址。
    address tokenAddr;
    // 上一个区块。
    uint256 lastBlock;
}
struct User {
    // 用户的本金。
    uint256 amount;
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

    // 池子的ID 序号。
    uint256 poolIdSeq;
    // 池子。key= poolID
    mapping(uint256 => Pool) poolMap;
    // 用户。key1= poolID key2= user
    mapping(uint256 => mapping(address => User)) userMap;

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

        poolIdSeq = 0; // 序号。
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
    function addPool(uint256 weight, address tokenAddr) public {
        require(weight > 0, "weight invalid");
        require(tokenAddr > address(0), "tokenAddr invalid");

        poolIdSeq++;
        uint256 poolIdNew = poolIdSeq;
        poolMap[poolIdNew] = Pool({
            weight: weight,
            tokenAddr: tokenAddr,
            lastBlock: block.number
        });
    }

    // 存款。本金。
    function deposite(uint256 poolId, uint256 amount) public payable {
        require(block.number >= startBlock, "block not start");
        require(block.number <= endBlock, "block be end");

        uint256 realAmount = amount;
        // 池子。
        Pool storage pool = poolMap[poolId];
        // eth。原生币
        if (poolId == 0) {
            require(amount == 0, "eth do not need amount");
            realAmount = msg.value; // eth
        }
        // token 代币。
        else {
            require(amount > 0, "token do need amount");
            require(pool.tokenAddr != address(0), "pool not found");
        }

        // 用户
        User storage user = userMap[poolId][msg.sender];
        // 本金。
        user.amount += realAmount;
    }
}
