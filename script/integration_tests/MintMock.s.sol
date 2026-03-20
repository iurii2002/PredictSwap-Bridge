// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script, console} from "forge-std/Script.sol";

interface IMockOpinion {
    function mint(address to, uint256 id, uint256 amount) external;
    function balanceOf(address account, uint256 id) external view returns (uint256);
}

contract MintMock is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address mock = vm.envAddress("OPINION_CONTRACT");
        address recipient = vm.envAddress("OWNER_ADDRESS");

        // Token ID and amount to mint — match whatever ID your OpinionEscrow expects
        uint256 tokenIdYes = 68227038457866748595233145251243944054564947305383894629176574093714476769147;
        uint256 amountYes = 1_000 * 1e18;

        vm.startBroadcast(deployerKey);
        IMockOpinion(mock).mint(recipient, tokenIdYes, amountYes);
        vm.stopBroadcast();

        uint256 balYes = IMockOpinion(mock).balanceOf(recipient, tokenIdYes);
        console.log("Minted tokenId:", tokenIdYes);
        console.log("Balance of recipient:", balYes);

        // Token ID and amount to mint — match whatever ID your OpinionEscrow expects
        uint256 tokenIdNo = 23295406450705254064374249781739843340364170407721892525550504746101807113177;
        uint256 amountNo = 1_000 * 1e18;

        vm.startBroadcast(deployerKey);
        IMockOpinion(mock).mint(recipient, tokenIdNo, amountNo);
        vm.stopBroadcast();
        uint256 balNo = IMockOpinion(mock).balanceOf(recipient, tokenIdNo);
        console.log("Minted tokenId:", tokenIdNo);
        console.log("Balance of recipient:", balNo);
    }
}