// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {OpinionEscrow} from "../src/OpinionEscrow.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";

contract DeployBSC is Script {
    using OptionsBuilder for bytes;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address lzEndpoint = vm.envAddress("BSC_LZ_ENDPOINT");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address opinionContract = vm.envAddress("OPINION_CONTRACT");
        uint32 polygonEid = uint32(vm.envUint("POLYGON_EID"));

        vm.startBroadcast(deployerKey);

        OpinionEscrow escrow = new OpinionEscrow(lzEndpoint, owner, opinionContract, polygonEid);

        // Set enforced options — ensures every lock() call provides enough gas on Polygon
        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam({
            eid: polygonEid,
            msgType: escrow.SEND(),
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(escrow.dstGasLimit(), 0)
        });
        escrow.setEnforcedOptions(opts);

        console.log("=== BSC Deployment ===");
        console.log("OpinionEscrow:", address(escrow));
        console.log("opinionContract:", address(opinionContract));
        console.log("Owner:", owner);
        console.log("LZ Endpoint:", lzEndpoint);
        console.log("Polygon EID:", polygonEid);
        console.log("EnforcedOptions: set (500k gas for lzReceive on Polygon)");
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Deploy Polygon contracts (DeployPolygon.s.sol)");
        console.log("2. Set peers: escrow.setPeer(polygonEid, bytes32(bridgeReceiverAddress))");

        vm.stopBroadcast();
    }
}