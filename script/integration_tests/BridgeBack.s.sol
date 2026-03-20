// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script, console} from "forge-std/Script.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

interface IWrappedToken {
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function setApprovalForAll(address operator, bool approved) external;
}

interface IBridgeReceiver {
    function quoteBridgeBackFee(
        uint256 _tokenId,
        uint256 _amount,
        address _bscRecipient,
        bytes calldata _options
    ) external view returns (MessagingFee memory fee);

    function bridgeBack(
        uint256 _tokenId,
        uint256 _amount,
        address _bscRecipient,
        bytes calldata _options
    ) external payable;
}

contract BridgeBack is Script {
    using OptionsBuilder for bytes;

    function run() external {
        uint256 deployerKey    = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address wrappedToken   = vm.envAddress("WRAPPED_OPINION_TOKEN_ADDRESS");
        address bridgeReceiver = vm.envAddress("BRIDGE_RECEIVER_ADDRESS");
        address self           = vm.envAddress("OWNER_ADDRESS");

        uint256 tokenId = 68227038457866748595233145251243944054564947305383894629176574093714476769147;
        uint256 amount  = 50; // bridge back half

        // bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        bytes memory options = new bytes(0);

        uint256 bal = IWrappedToken(wrappedToken).balanceOf(self, tokenId);
        console.log("Wrapped token balance:", bal);
        require(bal >= amount, "Insufficient wrapped balance");

        MessagingFee memory fee = IBridgeReceiver(bridgeReceiver).quoteBridgeBackFee(
            tokenId, amount, self, options
        );
        uint256 feeWithBuffer = fee.nativeFee * 110 / 100;
        console.log("LZ fee (wei):", fee.nativeFee);
        console.log("Fee with buffer:", feeWithBuffer);

        vm.startBroadcast(deployerKey);
        // BridgeReceiver burns directly from msg.sender — no approval needed
        IBridgeReceiver(bridgeReceiver).bridgeBack{value: feeWithBuffer}(
            tokenId, amount, self, options
        );
        vm.stopBroadcast();

        console.log("Bridge back tx sent!");
        console.log("Monitor: https://testnet.layerzeroscan.com");
    }
}