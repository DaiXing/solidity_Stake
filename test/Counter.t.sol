// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Counter} from "../src/Counter.sol";
import {StakeV1} from "../src/StakeV1.sol";
import {IStake} from "../src/IStake.sol";
import {RewardERC20} from "../src/RewardERC20.sol";
import {PoolERC20} from "../src/PoolERC20.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CounterTest is Test {
    Counter public counter;

    StakeV1 stakeV1; // 逻辑合约。
    address stakeV1Addr;

    ERC1967Proxy proxy; // 代理合约。
    address proxyAddr;
    IStake stake; // 接口。

    RewardERC20 rewardERC20; // 利息合约。
    PoolERC20 poolERC20A; // 本金合约。
    PoolERC20 poolERC20B; // 本金合约。

    // 用户。
    address userOwner = address(0xFF);
    address userJack = address(0xAA);
    address userTom = address(0xBB);

    function setUp() public {
        vm.startPrank(userOwner);

        // 利息合约。
        rewardERC20 = new RewardERC20();

        // 本金合约。
        poolERC20A = new PoolERC20();
        poolERC20B = new PoolERC20();

        // 逻辑合约。
        stakeV1 = new StakeV1();
        stakeV1Addr = address(stakeV1);

        // 代理合约。
        bytes memory funcData = abi.encodeWithSignature(
            "initialize(uint256,uint256,uint256,address)",
            block.number + 3,
            block.number + 8,
            100,
            address(rewardERC20)
        );
        proxy = new ERC1967Proxy(stakeV1Addr, funcData);
        proxyAddr = address(proxy);

        // 接口。
        stake = IStake(proxyAddr);

        // ETH 池子。
        stake.addPool(20, address(0), 10, 2);

        // ERC20 池子。
        stake.addPool(30, address(poolERC20A), 10, 2);
        stake.addPool(50, address(poolERC20B), 10, 2);

        vm.stopPrank();
    }

    function test_Increment() public {
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function testFuzz_SetNumber(uint256 x) public {
        counter.setNumber(x);
        assertEq(counter.number(), x);
    }
}
