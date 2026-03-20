// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script, console} from "forge-std/Script.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

interface IERC1155 {
    function setApprovalForAll(address operator, bool approved) external;
    function balanceOf(address account, uint256 id) external view returns (uint256);
}

interface IOpinionEscrow {
    function quoteLockFee(
        uint256 _tokenId,
        uint256 _amount,
        address _polygonRecipient,
        bytes calldata _options
    ) external view returns (MessagingFee memory fee);

    function lock(
        uint256 _tokenId,
        uint256 _amount,
        address _polygonRecipient,
        bytes calldata _options
    ) external payable;
}

contract BridgeTokens is Script {
    using OptionsBuilder for bytes;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address mock   = vm.envAddress("OPINION_CONTRACT");
        address escrow = vm.envAddress("OPINION_ESCROW_ADDRESS");
        address self   = vm.envAddress("OWNER_ADDRESS");

        uint256 tokenId = 68227038457866748595233145251243944054564947305383894629176574093714476769147;
        uint256 amount  = 100 * 1e18;

        // Correct LZ v2 options via OptionsBuilder
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        console.logBytes(options); // log so you can verify the encoding

        uint256 bal = IERC1155(mock).balanceOf(self, tokenId);
        console.log("Balance before bridge:", bal);
        require(bal >= amount, "Insufficient balance");

        MessagingFee memory fee = IOpinionEscrow(escrow).quoteLockFee(tokenId, amount, self, options);
        uint256 feeWithBuffer = fee.nativeFee * 110 / 100;
        console.log("LZ nativeFee (wei):", fee.nativeFee);
        console.log("Fee with 10% buffer:", feeWithBuffer);

        vm.startBroadcast(deployerKey);
        IERC1155(mock).setApprovalForAll(escrow, true);
        IOpinionEscrow(escrow).lock{value: feeWithBuffer}(tokenId, amount, self, options);
        vm.stopBroadcast();

        console.log("Bridge tx sent. Monitor:");
        console.log("https://testnet.layerzeroscan.com");
    }
}