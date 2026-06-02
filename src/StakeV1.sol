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
    // 最后更新的区块。
    uint256 lastUpdateBlock;
    // 本金。累加。
    uint256 totalAmount;
    // 每个本金的利息。累计。
    // 核心原则：在需要计算用户奖励之前，确保 rewardPerShare 是最新的。
    uint256 rewardPerAmount;
}
struct User {
    // 本金。
    uint256 amount;
    // 利息。未结算。
    uint256 pendingRewards;
    // 利息。已结算。
    uint256 finishedRewards;
}
contract StackV1 {
    using Strings for uint256;
    using Math for uint256;
    uint256 constant e18 = 1 ether;
    uint256 constant ETH_POOL_ID = 0;

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
        address _rewardAddr,
        uint256 _ethPoolWeight
    ) public {
        require(_startBlock > block.number, "_startBlock invalid");
        require(_endBlock < block.number, "_endBlock invalid");
        require(_rewardPerBlock > 0, "_rewardPerBlock invalid");
        require(_rewardAddr != address(0), "_rewardAddr invalid");
        require(_ethPoolWeight > 0, "_ethPoolWeight invalid");

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

        // 默认创建eth池子。
        poolMap[ETH_POOL_ID] = Pool({
            weight: _ethPoolWeight, // 权重。
            tokenAddr: address(0),
            lastUpdateBlock: block.number,
            rewardPerAmount: 0,
            totalAmount: 0
        });
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
            lastUpdateBlock: block.number,
            rewardPerAmount: 0,
            totalAmount: 0
        });
    }

    // 存款。本金。
    // 存款后，新本金只会参与未来的奖励分配，不会稀释用户已获得的奖励。
    // 必须先结算利息。
    function deposite(
        uint256 poolId,
        uint256 amount
    ) public payable updateRewards(poolId) {
        require(block.number >= startBlock, "block not start");
        require(block.number <= endBlock, "block be end");

        uint256 realAmount = amount;
        // 池子。
        Pool storage pool = poolMap[poolId];
        // eth。原生币
        if (poolId == ETH_POOL_ID) {
            require(amount == 0, "eth do not need amount");
            require(msg.value > 0, "eth value invalid");
            realAmount = msg.value; // eth
        }
        // token 代币。
        else {
            require(amount > 0, "token do need amount");
            require(pool.tokenAddr != address(0), "pool not found");

            // token转到本合约。
            IERC20 erc20 = IERC20(pool.tokenAddr);
            bool ok = erc20.transferFrom(msg.sender, address(this), realAmount);
            require(ok, "transferFrom fail");
        }

        // 用户
        User storage user = userMap[poolId][msg.sender];
        // 本金。
        user.amount += realAmount;
        pool.totalAmount += realAmount;

        // 当前利息已经结算了。下个阶段还未开始。
        user.finishedRewards = (pool.rewardPerAmount * user.amount) / e18;
    }

    // 取款。本金。
    // 必须先结算利息。
    function withdraw(
        uint256 poolId,
        uint256 amount
    ) public updateRewards(poolId) {
        require(block.number >= startBlock, "block not start");
        require(amount > 0, "amount invalid");

        // 池子。
        Pool storage pool = poolMap[poolId];
        // 用户
        User storage user = userMap[poolId][msg.sender];

        require(amount <= user.amount, "user amount not enough");

        // 本金。
        user.amount -= amount;
        pool.totalAmount -= amount;

        // 当前利息已经结算了。下个阶段还未开始。
        user.finishedRewards = (pool.rewardPerAmount * user.amount) / e18;

        // eth。原生币
        if (poolId == ETH_POOL_ID) {
            // 转账。
            (bool ok, ) = payable(msg.sender).call{value: amount}("");
            require(ok, "eth call fail");
        }
        // token 代币。
        else {
            // token转到用户。
            IERC20 erc20 = IERC20(pool.tokenAddr);
            bool ok = erc20.transferFrom(address(this), msg.sender, amount);
            require(ok, "transferFrom fail");
        }
    }

    // 获得利息。
    function claimRewards(uint256 poolId) public updateRewards(poolId) {
        // 池子。
        Pool storage pool = poolMap[poolId];
        // 用户
        User storage user = userMap[poolId][msg.sender];

        // 用户的未提取的利息。
        uint256 pending = user.pendingRewards;
        // 清空利息。
        user.pendingRewards = 0;

        // 把利息发给用户。
        bool ok = IERC20(rewardAddr).transfer(msg.sender, pending);
        require(ok, "transfer fail");
    }

    // 全部的权重。
    function getTotalWeight() private returns (uint256 weightSum) {
        // 累加总权重。
        for (uint256 index = 0; index <= poolIdSeq; ++index) {
            Pool storage pool = poolMap[index];
            weightSum += pool.weight;
        }
    }

    // 计算利息。 每个用户操作前，触发更新自己的利息。
    modifier updateRewards(uint256 poolId) {
        // 更新池子。
        updatePool(poolId);
        // 更新用户。
        updateUser(poolId);
        _;
    }

    // 更新单个池子。
    function updatePool(uint256 poolId) private {
        Pool storage pool = poolMap[poolId];
        require(pool.weight > 0, "pool not found");

        // 区块不对。
        if (block.number <= pool.lastUpdateBlock) {
            return;
        }
        // 没有本金。
        if (pool.totalAmount == 0) {
            pool.lastUpdateBlock = block.number;
            return;
        }

        // 区块的间隔。
        uint256 offBlock = block.number - pool.lastUpdateBlock;
        pool.lastUpdateBlock = block.number;

        // 本次的利息。
        uint256 offRewards = offBlock * rewardPerBlock;
        if (offRewards == 0) {
            return;
        }

        // 按权重，分配给本池子。
        uint256 weightSum = getTotalWeight();
        uint256 rewardsThisPool = (offRewards * pool.weight) / weightSum;

        // 更新每份本金的利息。
        // 先用 e18 扩大，防止精度丢失。
        pool.rewardPerAmount += (rewardsThisPool * e18) / pool.totalAmount;
    }

    // 用户存款取款，先结算利息。 只更新自己。
    function updateUser(uint256 poolId) private {
        Pool storage pool = poolMap[poolId];
        User storage user = userMap[poolId][msg.sender];

        // 计算用户的应得利息。 【核心】
        // 用户的总利息
        uint256 totalRewards = (pool.rewardPerAmount * user.amount) / e18; // 缩小精度。
        // 总利息减去已结算的利息，等于本次增加的利息
        uint256 pending = totalRewards - user.finishedRewards;
        // 增加的利息
        user.pendingRewards += pending;
        // 计算完成。
        user.finishedRewards = totalRewards;
    }

    // 【废弃】
    // 更新全部池子。主要是计算利息。
    // 改为 按需计费。只更新单个池子。
    function updateAllPool() private {
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
            updateAllUserInPool(pool, rewardForPool);
        }

        // 更新标记。
        lastUpdateBlock = endBlock2;
    }

    // 【废弃】
    // 错误。不要一次性都分配，因为用户可能非常多，几百万。
    // 改为懒处理。按需分配。
    // 把利息，分配给用户。
    function updateAllUserInPool(
        Pool storage pool,
        uint256 rewardForPool
    ) private {}
}
