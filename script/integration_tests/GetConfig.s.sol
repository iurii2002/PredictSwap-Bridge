// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {ExecutorConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";

contract GetConfigScript is Script {

    function getPolygonReceive() external view {
        address endpoint = vm.envAddress("POLYGON_LZ_ENDPOINT");
        address oapp     = vm.envAddress("BRIDGE_RECEIVER_ADDRESS");
        address lib      = vm.envAddress("POLYGON_RECEIVE_LIB");
        uint32  eid      = uint32(vm.envUint("BSC_EID"));
        console.log("Data for Polygon Receive");
        _printULN(endpoint, oapp, lib, eid);
    }

    function getPolygonSend() external view {
        address endpoint = vm.envAddress("POLYGON_LZ_ENDPOINT");
        address oapp     = vm.envAddress("BRIDGE_RECEIVER_ADDRESS");
        address lib      = vm.envAddress("POLYGON_SEND_LIB");
        uint32  eid      = uint32(vm.envUint("BSC_EID"));
        console.log("Data for Polygon Send");
        _printULN(endpoint, oapp, lib, eid);
        _printExecutor(endpoint, oapp, lib, eid);
    }

    function getBSCSend() external view {
        address endpoint = vm.envAddress("BSC_LZ_ENDPOINT");
        address oapp     = vm.envAddress("OPINION_ESCROW_ADDRESS");
        address lib      = vm.envAddress("BSC_SEND_LIB");
        uint32  eid      = uint32(vm.envUint("POLYGON_EID"));
        console.log("Data for BSC Send");
        _printULN(endpoint, oapp, lib, eid);
        _printExecutor(endpoint, oapp, lib, eid);
    }

    function getBSCReceive() external view {
        address endpoint = vm.envAddress("BSC_LZ_ENDPOINT");
        address oapp     = vm.envAddress("OPINION_ESCROW_ADDRESS");
        address lib      = vm.envAddress("BSC_RECEIVE_LIB");
        uint32  eid      = uint32(vm.envUint("POLYGON_EID"));
        console.log("Data for BSC Receive");
        _printULN(endpoint, oapp, lib, eid);
    }

    function _printULN(address endpoint, address oapp, address lib, uint32 eid) internal view {
        bytes memory config = ILayerZeroEndpointV2(endpoint).getConfig(oapp, lib, eid, 2);
        UlnConfig memory uln = abi.decode(config, (UlnConfig));
        console.log("Confirmations:", uln.confirmations);
        console.log("Required DVN Count:", uln.requiredDVNCount);
        for (uint i = 0; i < uln.requiredDVNs.length; i++) {
            console.logAddress(uln.requiredDVNs[i]);
        }
    }

    function _printExecutor(address endpoint, address oapp, address lib, uint32 eid) internal view {
        bytes memory config = ILayerZeroEndpointV2(endpoint).getConfig(oapp, lib, eid, 1);
        ExecutorConfig memory exec = abi.decode(config, (ExecutorConfig));
        console.log("maxMessageSize:", exec.maxMessageSize);
        console.log("Executor:", exec.executor);
    }

}