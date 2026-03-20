// script/DeployMockOpinion.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script, console} from "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract MockOpinion is ERC1155 {
    constructor() ERC1155("https://mock.uri/{id}") {}

    function mint(address to, uint256 id, uint256 amount) external {
        _mint(to, id, amount, "");
    }
}

contract DeployMockOpinion is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        MockOpinion mock = new MockOpinion();
        console.log("MockOpinion:", address(mock));
        vm.stopBroadcast();
    }
}