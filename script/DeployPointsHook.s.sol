// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {HookMiner} from "v4-hooks-public/src/utils/HookMiner.sol";

import {PointsHook} from "../src/PointsHook.sol";

/// @notice Mines a valid hook address for AFTER_SWAP_FLAG (bit 6) and deploys
///         PointsHook via CREATE2 through Foundry's default deployer proxy.
///         Default target is Sepolia; broadcast requires PRIVATE_KEY in env.
contract DeployPointsHook is Script {
    /// @dev Canonical Uniswap v4 PoolManager on Sepolia (chain id 11155111).
    address constant POOL_MANAGER_SEPOLIA = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;

    /// @dev The CREATE2 Deployer Proxy that `new X{salt: s}` uses under the hood
    ///      during `forge script` broadcast. HookMiner.find must be told this
    ///      address so the mined salt lands the contract at the expected slot.
    address constant CREATE2_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external {
        IPoolManager manager = IPoolManager(POOL_MANAGER_SEPOLIA);

        // Mine a salt so the deployed address encodes AFTER_SWAP_FLAG in its bottom bits.
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_PROXY, flags, type(PointsHook).creationCode, abi.encode(manager));

        console.log("PoolManager:", address(manager));
        console.log("Mined address:", hookAddress);
        console.logBytes32(salt);

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        PointsHook hook = new PointsHook{salt: salt}(manager);
        require(address(hook) == hookAddress, "DeployPointsHook: address mismatch");

        vm.stopBroadcast();

        console.log("Deployed at:", address(hook));
    }
}
