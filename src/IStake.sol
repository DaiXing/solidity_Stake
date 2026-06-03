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

    // 初始化。 代理模式，需要初始化。
    function initialize(
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _rewardPerBlock,
        address _rewardAddr
    ) external;

    function setStartBlock(uint256 _startBlock) external;
    function setEndBlock(uint256 _endBlock) external;
    function setRewardPerBlock(uint256 _rewardPerBlock) external;
    // 全部的权重。
    function getTotalWeight() external returns (uint256);

    // 添加1个池子。
    function addPool(
        uint256 weight,
        address tokenAddr, // 为0表示ETH
        uint256 _minDepositeAmount,
        uint256 _unstakeLockedBlocks
    ) external;

    // 存款。本金。 ETH
    function depositeEth() external payable;

    // 存款。本金。
    // 存款后，新本金只会参与未来的奖励分配，不会稀释用户已获得的奖励。
    // 必须先结算利息。
    function deposite(uint256 poolId, uint256 amount) external payable;

    // 解除质押。本金。
    // 先把请求，放入队列。防止挤兑。
    // 必须先结算利息。
    function unstake(uint256 poolId, uint256 amount) external;

    // 查询取款的本金。 返回申请的本金、可以领取的本金。
    function withdrawAmount(
        uint256 poolId
    ) external returns (uint256 requestAmount, uint256 pendingWithdrawAmount);

    // 取款。本金。
    // 必须先结算利息。
    // 只能拿走已经解锁的本金。
    function withdraw(uint256 poolId) external;

    // 获得利息。
    function claimRewards(uint256 poolId) external;
}
