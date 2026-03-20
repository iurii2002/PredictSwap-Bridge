// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {WrappedOpinionToken} from "../src/WrappedOpinionToken.sol";

contract WrappedOpinionTokenTest is Test {
    WrappedOpinionToken public token;
    address public owner = makeAddr("owner");
    address public bridge = makeAddr("bridge");
    address public user = makeAddr("user");
    address public opinionContract = makeAddr("opinionContract");
    address public attacker = makeAddr("attacker");

    address constant OPINION_CONTRACT = address(0xBEEF);
    uint256 constant OPINION_TOKEN_ID = 42;

    function setUp() public {
        vm.prank(owner);
        token = new WrappedOpinionToken(owner, opinionContract);

        vm.prank(owner);
        token.setBridge(bridge);
    }

    // ─── Mint ───

    function test_mint_success() public {
        vm.prank(bridge);
        token.mint(user, OPINION_TOKEN_ID, 1000);

        assertEq(token.balanceOf(user, OPINION_TOKEN_ID), 1000);
        assertEq(token.totalSupply(OPINION_TOKEN_ID), 1000);
    }

    function test_mint_multipleTimes() public {
        vm.startPrank(bridge);
        token.mint(user, OPINION_TOKEN_ID, 500);
        token.mint(user, OPINION_TOKEN_ID, 300);
        vm.stopPrank();

        assertEq(token.balanceOf(user, OPINION_TOKEN_ID), 800);
        assertEq(token.totalSupply(OPINION_TOKEN_ID), 800);
    }

    function test_mint_revertNotBridge() public {
        vm.prank(attacker);
        vm.expectRevert(WrappedOpinionToken.OnlyBridge.selector);
        token.mint(user, OPINION_TOKEN_ID, 100);
    }

    function test_mint_revertZeroAddress() public {
        vm.prank(bridge);
        vm.expectRevert(WrappedOpinionToken.ZeroAddress.selector);
        token.mint(address(0), OPINION_TOKEN_ID, 100);
    }

    function test_mint_revertZeroAmount() public {
        vm.prank(bridge);
        vm.expectRevert(WrappedOpinionToken.ZeroAmount.selector);
        token.mint(user, OPINION_TOKEN_ID, 0);
    }

    // ─── Burn ───

    function test_burn_success() public {
        vm.prank(bridge);
        token.mint(user, OPINION_TOKEN_ID, 1000);

        vm.prank(bridge);
        token.burn(user, OPINION_TOKEN_ID, 400);

        assertEq(token.balanceOf(user, OPINION_TOKEN_ID), 600);
        assertEq(token.totalSupply(OPINION_TOKEN_ID), 600);
    }

    function test_burn_revertNotBridge() public {
        vm.prank(bridge);
        token.mint(user, OPINION_TOKEN_ID, 100);

        vm.prank(attacker);
        vm.expectRevert(WrappedOpinionToken.OnlyBridge.selector);
        token.burn(user, OPINION_TOKEN_ID, 50);
    }

    function test_burn_revertInsufficientBalance() public {
        vm.prank(bridge);
        token.mint(user, OPINION_TOKEN_ID, 100);

        vm.prank(bridge);
        vm.expectRevert(); // ERC1155 insufficient balance
        token.burn(user, OPINION_TOKEN_ID, 200);
    }

    // ─── Admin ───

    function test_setBridge_revertsIfAlreadySet() public {     
        vm.prank(owner);   
        vm.expectRevert(WrappedOpinionToken.BridgeAlreadySet.selector);
        token.setBridge(makeAddr("anotherBridge")); // should revert
        vm.stopPrank();
    }

    function test_setBridge_revertNotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        token.setBridge(attacker);
    }

    function test_setBridge_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(WrappedOpinionToken.ZeroAddress.selector);
        token.setBridge(address(0));
    }
}
