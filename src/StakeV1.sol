// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// todo 怎么设置eth池？
struct Pool {
    // 权重。
    uint256 weight;
    // token合约地址。
    address tokenAddr;
    // 上一个区块。
    uint256 lastBlock;
    // 获得的利息。累加。
    uint256 rewardSum;
}
struct User {
    // 用户的本金。
    uint256 amount;
}
contract StackV1 {
    using Strings for uint256;
    using Math for uint256;
    uint256 constant e18 = 1 ether;

    // 区块。开始位置。
    uint256 startBlock;
    // 区块。结束位置。
    uint256 endBlock;
    // 每个区块的奖励。
    uint256 rewardPerBlock;
    // 奖励合约。发奖励。 IERC20
    address rewardAddr;
    // 是否需要更新池子。
    bool needUpdatePool;
    // 最后更新的区块。
    uint256 lastUpdateBlock;

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
        needUpdatePool = true;

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
            lastBlock: block.number,
            rewardSum: 0
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

    // 更新池子。主要是计算利息。
    function updatePool() private {
        // 未开始或已经结束。忽略。
        if (block.number <= startBlock || !needUpdatePool) {
            return;
        }

        uint256 endBlock2 = block.number;
        if (endBlock2 > endBlock) {
            endBlock2 = endBlock;
            // 结束了。
            needUpdatePool = false;
        }
        // 隔了几个块。
        uint256 offBlock = endBlock2 - startBlock;
        // 总利息。
        (bool ok, uint256 rewardTotal) = offBlock.tryMul(rewardPerBlock);
        require(ok, "rewardTotal error");

        // 累加总权重。
        uint256 weightSum = 0;
        for (uint256 index = 0; index <= poolIdSeq; ++index) {
            Pool storage pool = poolMap[index];
            weightSum += pool.weight;
        }

        // 把奖励分配给各个池子。
        for (uint256 index = 0; index <= poolIdSeq; ++index) {
            Pool storage pool = poolMap[index];
            // 池子本次的利息。
            uint256 rewardForPool = (rewardTotal * pool.weight) / weightSum;
            pool.rewardSum += rewardForPool;
            // 把利息，分配给用户。
            updateUser(pool, rewardForPool);
        }

        // 更新标记。
        lastUpdateBlock = endBlock2;
    }

    // 把利息，分配给用户。
    function updateUser(Pool storage pool, uint256 rewardForPool) private {}
}
