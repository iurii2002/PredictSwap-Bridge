// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {BridgeReceiver} from "../src/BridgeReceiver.sol";
import {WrappedOpinionToken} from "../src/WrappedOpinionToken.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";

/// @title DeployPolygon
/// @notice Deploys BridgeReceiver, WrappedOpinionToken on Polygon.
/// @dev Run with:
///      forge script script/DeployPolygon.s.sol:DeployPolygon --rpc-url $POLYGON_RPC_URL --broadcast --verify
///
/// Required environment variables:
///   DEPLOYER_PRIVATE_KEY   - Private key of the deployer
///   POLYGON_LZ_ENDPOINT    - LayerZero V2 endpoint address on Polygon (0x1a44076050125825900e736c501f859c50fE728c)
///   OWNER_ADDRESS          - Team multisig that will own the contracts
///   BSC_EID                - LayerZero endpoint ID for BSC (30102)
///   OPINION_ESCROW_ADDRESS - Address of the deployed OpinionEscrow on BSC (for peer setup)
contract DeployPolygon is Script {

    using OptionsBuilder for bytes;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address lzEndpoint = vm.envAddress("POLYGON_LZ_ENDPOINT");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address opinionContract = vm.envAddress("OPINION_CONTRACT");
        uint32 bscEid = uint32(vm.envUint("BSC_EID"));

        vm.startBroadcast(deployerKey);

        // 1. Deploy WrappedOpinionToken
        WrappedOpinionToken wrappedToken = new WrappedOpinionToken(owner, opinionContract);

        // 2. Deploy AddressRegistry
        // Depreciated

        // 3. Deploy BridgeReceiver
        BridgeReceiver receiver = new BridgeReceiver(lzEndpoint, owner, address(wrappedToken), bscEid);

        // 4. Authorize BridgeReceiver as the bridge on WrappedOpinionToken
        wrappedToken.setBridge(address(receiver));

        // Set enforced options — ensures every lock() call provides enough gas on Polygon
        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam({
            eid: bscEid,
            msgType: receiver.SEND(),
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(receiver.dstGasLimit(), 0)
        });
        receiver.setEnforcedOptions(opts);

        console.log("=== Polygon Deployment ===");
        console.log("WrappedOpinionToken:", address(wrappedToken));
        console.log("BridgeReceiver:", address(receiver));
        console.log("Owner:", owner);
        console.log("opinionContract:", opinionContract);
        console.log("LZ Endpoint:", lzEndpoint);
        console.log("BSC EID:", bscEid);
        console.log("EnforcedOptions: set (500k gas for lzReceive on BSC)");
        console.log("");
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Set peer on BridgeReceiver: receiver.setPeer(bscEid, bytes32(escrowAddress))");
        console.log("2. Set peer on OpinionEscrow (BSC): escrow.setPeer(polygonEid, bytes32(receiverAddress))");

        vm.stopBroadcast();
    }
}
