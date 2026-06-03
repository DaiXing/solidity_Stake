// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

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
    // 最新质押数量。
    uint256 minDepositeAmount;
    // 解质押，需要锁多少个block。
    uint256 unstakeLockedBlocks;
}

struct User {
    // 本金。
    uint256 amount;
    // 利息。未结算。
    uint256 pendingRewards;
    // 利息。已结算。
    uint256 finishedRewards;
    // 解质押的请求。
    UnstakeRequest[] unstakeRequests;
}

// 解质押的请求。 防止挤兑。
struct UnstakeRequest {
    // 金额。
    uint256 amount;
    // 解锁的区块。
    uint256 unlockBlock;
}

interface IStake {
    event SetStartBlock(address indexed user, uint256 startBlock);
    event SetEndBlock(address indexed user, uint256 endBlock);
    event SetRewardPerBlock(address indexed user, uint256 rewardPerBlock);

    event AddPool(
        address indexed user,
        uint256 indexed poolId,
        uint256 weight,
        address indexed tokenAddr,
        uint256 minDepositeAmount,
        uint256 unstakeLockedBlocks
    );
    event Deposite(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );
    event Unstake(address indexed user, uint256 indexed poolId, uint256 amount);
    event Withdraw(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );
    event ClaimRewards(
        address indexed user,
        uint256 indexed poolId,
        uint256 rewards
    );
}
