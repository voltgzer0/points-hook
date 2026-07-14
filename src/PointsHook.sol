// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-hooks-public/src/base/BaseHook.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";

import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

/// @title PointsHook — UHI cohort exercise, points hook with a referrer bonus.
/// @author voltgzer0
/// @notice Mints an ERC-1155 points token to a user when they buy TOKEN with ETH
///         (native-currency-0 pool with this hook attached), and — as the small
///         feature added on top of the canonical UHI example — pays a smaller
///         bonus to a referrer address the buyer opts in to name.
///
///         Encoding contract for `hookData`:
///           - empty bytes             -> nobody gets points
///           - abi.encode(user)        -> user gets 20% of ETH spent
///           - abi.encode(user, ref)   -> user gets 20%, referrer gets 5%
///
///         The referrer bonus is skipped when ref == address(0) or ref == user,
///         so the pattern degrades cleanly to the canonical single-address form.
contract PointsHook is BaseHook, ERC1155 {
    /// @dev Points minted to the buyer, in ppm of ETH spent (20% = 200_000 ppm).
    uint256 public constant USER_POINTS_PPM = 200_000;

    /// @dev Points minted to the referrer, in ppm of ETH spent (5% = 50_000 ppm).
    uint256 public constant REFERRER_POINTS_PPM = 50_000;

    /// @dev Divisor for ppm arithmetic.
    uint256 private constant PPM_DENOM = 1_000_000;

    constructor(IPoolManager _manager) BaseHook(_manager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function uri(uint256) public view virtual override returns (string memory) {
        return "https://api.example.com/token/{id}";
    }

    /// @dev afterSwap: mint user points on ETH -> TOKEN swaps, plus referrer bonus if opted in.
    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta delta, bytes calldata hookData)
        internal
        override
        returns (bytes4, int128)
    {
        // Only ETH-TOKEN pools with this hook attached (currency0 == 0x0).
        if (!key.currency0.isAddressZero()) return (this.afterSwap.selector, 0);

        // Only reward the ETH -> TOKEN direction (buying TOKEN with ETH).
        // In that direction, delta.amount0() is negative (ETH left the swapper);
        // the absolute value is the ETH they spent.
        int128 a0 = delta.amount0();
        if (a0 >= 0) return (this.afterSwap.selector, 0);
        uint256 ethSpent = uint256(int256(-a0));

        _assignPoints(key.toId(), hookData, ethSpent);
        return (this.afterSwap.selector, 0);
    }

    /// @dev Decodes `hookData` and mints:
    ///        - USER_POINTS_PPM of `ethSpent` to `user` (if `user != 0`)
    ///        - REFERRER_POINTS_PPM of `ethSpent` to `referrer` (if referrer valid)
    ///      Empty hookData mints nothing (per lesson contract).
    function _assignPoints(PoolId poolId, bytes calldata hookData, uint256 ethSpent) internal {
        if (hookData.length == 0) return;

        address user;
        address referrer;
        if (hookData.length == 32) {
            user = abi.decode(hookData, (address));
        } else {
            (user, referrer) = abi.decode(hookData, (address, address));
        }

        if (user == address(0)) return;

        uint256 tokenId = uint256(PoolId.unwrap(poolId));

        uint256 userPoints = (ethSpent * USER_POINTS_PPM) / PPM_DENOM;
        if (userPoints > 0) _mint(user, tokenId, userPoints, "");

        // Referrer bonus is skipped if unset OR if the buyer self-refers.
        if (referrer == address(0) || referrer == user) return;

        uint256 referrerPoints = (ethSpent * REFERRER_POINTS_PPM) / PPM_DENOM;
        if (referrerPoints > 0) _mint(referrer, tokenId, referrerPoints, "");
    }
}
