// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {OpinionEscrow} from "../src/OpinionEscrow.sol";
import {BridgeReceiver} from "../src/BridgeReceiver.sol";

/// @title SetPeers
/// @notice Configures LayerZero peers after both chains are deployed.
///         Run this twice: once targeting BSC, once targeting Polygon.
/// @dev
///   Set BSC peer:
///     CHAIN=bsc forge script script/SetPeers.s.sol:SetPeerBSC --rpc-url $BSC_RPC_URL --broadcast
///
///   Set Polygon peer:
///     CHAIN=polygon forge script script/SetPeers.s.sol:SetPeerPolygon --rpc-url $POLYGON_RPC_URL --broadcast
///
/// Required env vars for both:
///   DEPLOYER_PRIVATE_KEY, OPINION_ESCROW_ADDRESS, BRIDGE_RECEIVER_ADDRESS, POLYGON_EID, BSC_EID

contract SetPeerBSC is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address escrowAddr = vm.envAddress("OPINION_ESCROW_ADDRESS");
        address receiverAddr = vm.envAddress("BRIDGE_RECEIVER_ADDRESS");
        uint32 polygonEid = uint32(vm.envUint("POLYGON_EID"));

        OpinionEscrow escrow = OpinionEscrow(payable(escrowAddr));

        vm.startBroadcast(deployerKey);
        escrow.setPeer(polygonEid, bytes32(uint256(uint160(receiverAddr))));
        vm.stopBroadcast();

        console.log("OpinionEscrow peer set:");
        console.log("  Polygon EID:", polygonEid);
        console.log("  BridgeReceiver:", receiverAddr);
    }
}

contract SetPeerPolygon is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address escrowAddr = vm.envAddress("OPINION_ESCROW_ADDRESS");
        address receiverAddr = vm.envAddress("BRIDGE_RECEIVER_ADDRESS");
        uint32 bscEid = uint32(vm.envUint("BSC_EID"));

        BridgeReceiver receiver = BridgeReceiver(payable(receiverAddr));

        vm.startBroadcast(deployerKey);
        receiver.setPeer(bscEid, bytes32(uint256(uint160(escrowAddr))));
        vm.stopBroadcast();

        console.log("BridgeReceiver peer set:");
        console.log("  BSC EID:", bscEid);
        console.log("  OpinionEscrow:", escrowAddr);
    }
}
