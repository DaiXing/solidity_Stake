// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
// import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {Pool, User, UnstakeRequest, IStake} from "./IStake.sol";

// 质押。
contract StackV1 is IStake, AccessControl, UUPSUpgradeable {
    using Strings for uint256;
    using Math for uint256;

    // 算利息，增加精度。 10 ** 18
    uint256 constant E18 = 1 ether;
    // ETH 的池子。
    uint256 constant ETH_POOL_ID = 0;

    // 权限。
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 constant UPGRADE_ROLE = keccak256("UPGRADE_ROLE");

    // 区块。开始位置。
    uint256 public startBlock;
    // 区块。结束位置。
    uint256 public endBlock;
    // 每个区块的奖励。
    uint256 public rewardPerBlock;
    // 奖励合约。发奖励。 IERC20
    address public rewardAddr;
    // 总共的权重。减少遍历。
    uint256 public sumWeight;

    // 池子的ID 序号。
    uint256 public poolIdSeq;
    // 池子。key= poolID
    mapping(uint256 => Pool) public poolMap;
    // 用户。key1= poolID key2= user
    mapping(uint256 => mapping(address => User)) public userMap;

    // 初始化。 代理模式，需要初始化。
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

        // 权限。
        grantRole(ADMIN_ROLE, msg.sender);
        grantRole(UPGRADE_ROLE, msg.sender);
    }

    // 升级，需要权限。
    function _authorizeUpgrade(
        address impl
    ) internal override onlyRole(UPGRADE_ROLE) {}

    function setStartBlock(uint256 _startBlock) public onlyRole(ADMIN_ROLE) {
        require(_startBlock >= block.number, "_startBlock invalid");
        require(_startBlock < endBlock, "_startBlock invalid");
        startBlock = _startBlock;

        emit SetStartBlock(msg.sender, startBlock);
    }
    function setEndBlock(uint256 _endBlock) public onlyRole(ADMIN_ROLE) {
        require(_endBlock >= block.number, "_endBlock invalid");
        require(_endBlock > startBlock, "_endBlock invalid");
        endBlock = _endBlock;

        emit SetEndBlock(msg.sender, endBlock);
    }
    function setRewardPerBlock(
        uint256 _rewardPerBlock
    ) public onlyRole(ADMIN_ROLE) {
        require(_rewardPerBlock > 0, "_rewardPerBlock invalid");
        rewardPerBlock = _rewardPerBlock;

        emit SetRewardPerBlock(msg.sender, rewardPerBlock);
    }

    // 添加1个池子。
    function addPool(
        uint256 weight,
        address tokenAddr, // 为0表示ETH
        uint256 _minDepositeAmount,
        uint256 _unstakeLockedBlocks
    ) public onlyRole(ADMIN_ROLE) {
        require(weight > 0, "weight invalid");
        require(_minDepositeAmount > 0, "_minDepositeAmount invalid");
        require(_unstakeLockedBlocks > 0, "_unstakeLockedBlocks invalid");

        uint256 poolIdNew = 0;
        // ETH 池子。
        if (tokenAddr == address(0)) {
            // 不能重复。
            Pool storage pool = poolMap[poolIdNew];
            require(pool.weight == 0, "eth pool repeat");
        }
        // ERC20 池子。
        else {
            poolIdSeq++;
            poolIdNew = poolIdSeq;
        }

        // 判断起点。
        uint256 lastUpdateBlock2 = (block.number > startBlock)
            ? block.number
            : startBlock;

        poolMap[poolIdNew] = Pool({
            weight: weight,
            tokenAddr: tokenAddr,
            lastUpdateBlock: lastUpdateBlock2,
            rewardPerAmount: 0,
            totalAmount: 0,
            minDepositeAmount: _minDepositeAmount,
            unstakeLockedBlocks: _unstakeLockedBlocks
        });
        sumWeight += weight;

        emit AddPool(
            msg.sender,
            poolIdNew,
            weight,
            tokenAddr,
            _minDepositeAmount,
            _unstakeLockedBlocks
        );
    }

    // 存款。本金。 ETH
    function depositeEth() public payable {
        deposite(ETH_POOL_ID, 0);
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
            require(realAmount < pool.minDepositeAmount, "eth value too small");
        }
        // token 代币。
        else {
            require(amount > 0, "token do need amount");
            require(pool.tokenAddr != address(0), "pool not found");
            require(realAmount < pool.minDepositeAmount, "amount too small");

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
        user.finishedRewards = (pool.rewardPerAmount * user.amount) / E18;

        emit Deposite(msg.sender, poolId, realAmount);
    }

    // 解除质押。本金。
    // 先把请求，放入队列。防止挤兑。
    // 必须先结算利息。
    function unstake(
        uint256 poolId,
        uint256 amount
    ) public updateRewards(poolId) {
        require(amount > 0, "amount invalid");
        // 池子。
        Pool storage pool = poolMap[poolId];
        // 用户
        User storage user = userMap[poolId][msg.sender];

        require(amount <= user.amount, "amount balance not enougth");

        // 减去本金
        user.amount -= amount;
        pool.totalAmount -= amount;
        // 本金变了。利息需要更新。等待下次计算利息。
        user.finishedRewards = (user.amount * pool.rewardPerAmount) / 1 ether;

        // 排队。等待解锁。
        user.unstakeRequests.push(
            UnstakeRequest({
                amount: amount,
                unlockBlock: block.number + pool.unstakeLockedBlocks
            })
        );

        emit Unstake(msg.sender, poolId, amount);
    }

    // 查询取款的本金。 返回申请的本金、可以领取的本金。
    function withdrawAmount(
        uint256 poolId
    )
        public
        view
        returns (uint256 requestAmount, uint256 pendingWithdrawAmount)
    {
        // 用户
        User storage user = userMap[poolId][msg.sender];

        uint256 len = user.unstakeRequests.length;
        for (uint256 k = 0; k < len; len++) {
            requestAmount += user.unstakeRequests[k].amount;
            // 到达解锁了。 可以取款了。
            if (block.number >= user.unstakeRequests[k].unlockBlock) {
                pendingWithdrawAmount += user.unstakeRequests[k].amount;
            }
        }
    }

    // 取款。本金。
    // 必须先结算利息。
    // 只能拿走已经解锁的本金。
    function withdraw(uint256 poolId) public updateRewards(poolId) {
        require(block.number >= endBlock, "block not end");

        // 池子。
        Pool storage pool = poolMap[poolId];
        // 用户
        User storage user = userMap[poolId][msg.sender];

        // 计算已经解锁的本金。
        uint256 amount = 0;
        uint256 len = user.unstakeRequests.length;
        // 已经解锁的，需要弹出。
        uint256 popCount = 0;
        for (uint256 k = 0; k < len; k++) {
            // 还没有到解锁时间。
            if (user.unstakeRequests[k].unlockBlock > block.number) {
                break;
            }
            amount += user.unstakeRequests[k].amount;
            popCount++;
        }

        // 没有待领取的本金。 未解锁或领完了。
        if (amount == 0) {
            return;
        }

        // 清理已经解锁的。
        for (uint256 m = 0; m < len - popCount; m++) {
            user.unstakeRequests[m] = user.unstakeRequests[m + popCount];
        }
        for (uint256 n = 0; n < popCount; n++) {
            user.unstakeRequests.pop();
        }

        // 本金。
        user.amount -= amount;
        pool.totalAmount -= amount;

        // 当前利息已经结算了。下个阶段还未开始。
        user.finishedRewards = (pool.rewardPerAmount * user.amount) / E18;

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

        emit Withdraw(msg.sender, poolId, amount);
    }

    // 获得利息。
    function claimRewards(uint256 poolId) public updateRewards(poolId) {
        // 用户
        User storage user = userMap[poolId][msg.sender];

        // 用户的未提取的利息。
        uint256 rewards = user.pendingRewards;
        // 清空利息。
        user.pendingRewards = 0;

        // 把利息发给用户。
        bool ok = IERC20(rewardAddr).transfer(msg.sender, rewards);
        require(ok, "transfer fail");

        emit ClaimRewards(msg.sender, poolId, rewards);
    }

    // 全部的权重。
    function getTotalWeight() public view returns (uint256) {
        // 累加总权重。
        // for (uint256 index = 0; index <= poolIdSeq; ++index) {
        //     Pool storage pool = poolMap[index];
        //     weightSum += pool.weight;
        // }

        // 减少遍历。
        return sumWeight;
    }

    // 计算利息。 每个用户操作前，触发更新自己的利息。
    modifier updateRewards(uint256 poolId) {
        updateRewards_(poolId);
        _;
    }

    // 计算利息。 每个用户操作前，触发更新自己的利息。
    function updateRewards_(uint256 poolId) private {
        // 更新池子。
        updatePool(poolId);
        // 更新用户。
        updateUser(poolId);
    }

    // 更新单个池子。
    function updatePool(uint256 poolId) private {
        Pool storage pool = poolMap[poolId];
        require(pool.weight > 0, "pool not found");

        // 区块不对。
        if (block.number <= pool.lastUpdateBlock) {
            return;
        }
        if (block.number > endBlock) {
            return;
        }
        // 暂存。
        uint256 lastUpdateBlock2 = pool.lastUpdateBlock;
        pool.lastUpdateBlock = block.number;
        // 没有本金。
        if (pool.totalAmount == 0) {
            return;
        }

        // todo 起始点block，应该用哪个？如果当前池子很老，则利息应该占大头。

        // 区块的间隔。 只看单个池子。
        uint256 offBlock = block.number - lastUpdateBlock2;

        // 本次的利息。
        uint256 offRewards = offBlock * rewardPerBlock;
        if (offRewards == 0) {
            return;
        }

        // 按权重，分配给本池子。
        uint256 weightSum = getTotalWeight();
        uint256 rewardsThisPool = (offRewards * pool.weight) / weightSum;

        // 更新每份本金的利息。
        // 先用 E18 扩大，防止精度丢失。
        pool.rewardPerAmount += (rewardsThisPool * E18) / pool.totalAmount;
    }

    // 用户存款取款，先结算利息。 只更新自己。
    function updateUser(uint256 poolId) private {
        Pool storage pool = poolMap[poolId];
        User storage user = userMap[poolId][msg.sender];

        // 计算用户的应得利息。 【核心】
        // 用户的总利息
        uint256 totalRewards = (pool.rewardPerAmount * user.amount) / E18; // 缩小精度。
        // 总利息减去已结算的利息，等于本次增加的利息
        uint256 pending = totalRewards - user.finishedRewards;
        // 增加的利息
        user.pendingRewards += pending;
        // 计算完成。
        user.finishedRewards = totalRewards;
    }
}
