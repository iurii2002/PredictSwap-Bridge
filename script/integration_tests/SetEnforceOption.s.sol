// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {OpinionEscrow} from "../../src/OpinionEscrow.sol";
import {BridgeReceiver} from "../../src/BridgeReceiver.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {EnforcedOptionParam} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";

contract SetEnforcedOptions is Script {
    using OptionsBuilder for bytes;

    function setBSC() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address escrowAddr  = vm.envAddress("OPINION_ESCROW_ADDRESS");
        uint32 polygonEid   = uint32(vm.envUint("POLYGON_EID"));

        OpinionEscrow escrow = OpinionEscrow(payable(escrowAddr));

        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam({
            eid: polygonEid,
            msgType: escrow.SEND(),
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(escrow.dstGasLimit(), 0)
        });

        vm.startBroadcast(deployerKey);
        escrow.setEnforcedOptions(opts);
        vm.stopBroadcast();

        console.log("EnforcedOptions set on OpinionEscrow");
        console.log("  Gas limit:", escrow.dstGasLimit());
        console.log("  Destination EID:", polygonEid);
    }

    function setPolygon() external {
        uint256 deployerKey  = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address receiverAddr = vm.envAddress("BRIDGE_RECEIVER_ADDRESS");
        uint32 bscEid        = uint32(vm.envUint("BSC_EID"));

        BridgeReceiver receiver = BridgeReceiver(payable(receiverAddr));

        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](1);
        opts[0] = EnforcedOptionParam({
            eid: bscEid,
            msgType: receiver.SEND(),
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(receiver.dstGasLimit(), 0)
        });

        vm.startBroadcast(deployerKey);
        receiver.setEnforcedOptions(opts);
        vm.stopBroadcast();

        console.log("EnforcedOptions set on BridgeReceiver");
        console.log("  Gas limit:", receiver.dstGasLimit());
        console.log("  Destination EID:", bscEid);
    }
}