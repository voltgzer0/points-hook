// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {HookMiner} from "v4-hooks-public/src/utils/HookMiner.sol";

import {PointsHook} from "../src/PointsHook.sol";

contract PointsHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;

    PointsHook hook;
    MockERC20 token;
    Currency c1;
    PoolKey ethKey;
    PoolId ethPid;
    uint256 tokenId;

    address user = makeAddr("user");
    address referrer = makeAddr("referrer");

    function setUp() public {
        deployFreshManagerAndRouters();

        token = new MockERC20("Test Token", "TKN", 18);
        token.mint(address(this), 1_000_000 ether);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        token.approve(address(swapRouter), type(uint256).max);
        c1 = Currency.wrap(address(token));

        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(PointsHook).creationCode,
            abi.encode(IPoolManager(address(manager)))
        );
        hook = new PointsHook{salt: salt}(IPoolManager(address(manager)));
        require(address(hook) == hookAddress, "hook address mismatch");

        (ethKey, ethPid) = initPoolAndAddLiquidityETH(
            CurrencyLibrary.ADDRESS_ZERO,
            c1,
            IHooks(address(hook)),
            3000,
            SQRT_PRICE_1_1,
            10 ether
        );

        tokenId = uint256(PoolId.unwrap(ethPid));
        vm.deal(address(this), 1_000 ether);
    }

    // Swap 0.1 ETH for TOKEN and return the exact ETH the pool took (as reported by the delta).
    function _swapEthForToken(uint256 ethIn, bytes memory hookData) internal returns (uint256 ethSpent) {
        uint256 balBefore = address(this).balance;

        swapRouter.swap{value: ethIn}(
            ethKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(ethIn),
                sqrtPriceLimitX96: MIN_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 balAfter = address(this).balance;
        ethSpent = balBefore - balAfter;
    }

    function test_userGetsTwentyPercentOnEthToTokenSwap() public {
        uint256 ethIn = 0.1 ether;
        bytes memory hookData = abi.encode(user);

        uint256 spent = _swapEthForToken(ethIn, hookData);

        assertEq(hook.balanceOf(user, tokenId), (spent * 200_000) / 1_000_000);
        assertEq(hook.balanceOf(referrer, tokenId), 0);
    }

    function test_referrerGetsFivePercentWhenSet() public {
        uint256 ethIn = 0.1 ether;
        bytes memory hookData = abi.encode(user, referrer);

        uint256 spent = _swapEthForToken(ethIn, hookData);

        assertEq(hook.balanceOf(user, tokenId), (spent * 200_000) / 1_000_000);
        assertEq(hook.balanceOf(referrer, tokenId), (spent * 50_000) / 1_000_000);
    }

    function test_noReferrerBonusWhenReferrerZero() public {
        uint256 ethIn = 0.1 ether;
        bytes memory hookData = abi.encode(user, address(0));

        uint256 spent = _swapEthForToken(ethIn, hookData);

        assertEq(hook.balanceOf(user, tokenId), (spent * 200_000) / 1_000_000);
        assertEq(hook.balanceOf(address(0), tokenId), 0);
    }

    function test_noReferrerBonusWhenSelfRefer() public {
        uint256 ethIn = 0.1 ether;
        bytes memory hookData = abi.encode(user, user);

        uint256 spent = _swapEthForToken(ethIn, hookData);

        // Self-refer collapses to the plain-user case: only 20%, no bonus mint.
        assertEq(hook.balanceOf(user, tokenId), (spent * 200_000) / 1_000_000);
    }

    function test_emptyHookDataMintsNothing() public {
        uint256 spent = _swapEthForToken(0.1 ether, "");
        // Nobody was named, nobody gets minted.
        assertEq(hook.balanceOf(user, tokenId), 0);
        assertEq(hook.balanceOf(referrer, tokenId), 0);
        assertGt(spent, 0);
    }

}
