// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BridgeReceiver} from "../src/BridgeReceiver.sol";
import {WrappedOpinionToken} from "../src/WrappedOpinionToken.sol";
import {MockEndpointV2} from "./mocks/MockEndpointV2.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

contract BridgeReceiverTest is Test {
    BridgeReceiver public receiver;
    WrappedOpinionToken public wrappedToken;
    MockEndpointV2 public polyEndpoint;
    bytes32 public escrowPeer;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public opinionEscrow = makeAddr("opinionEscrow");
    address public opinionContract = makeAddr("opinionContract");

    uint32 constant BSC_EID = 30102;
    uint32 constant POLYGON_EID = 30109;

    address constant OPINION_CONTRACT = address(0xBEEF);
    uint256 constant OPINION_TOKEN_ID = 42;
    
        // options
    bytes public _option = abi.encodePacked(
        uint16(0x0003),
        uint8(0x01),
        uint16(0x0011),
        uint8(0x01),
        uint128(200_000)
    );

    function setUp() public {
        polyEndpoint = new MockEndpointV2(POLYGON_EID);
        
        vm.startPrank(owner);
        wrappedToken = new WrappedOpinionToken(owner, opinionContract);
        receiver = new BridgeReceiver(address(polyEndpoint), owner, address(wrappedToken), BSC_EID);

        escrowPeer = bytes32(uint256(uint160(opinionEscrow)));  // precomputed once

        // Authorize receiver as the bridge on WrappedOpinionToken
        wrappedToken.setBridge(address(receiver));

        // Set OpinionEscrow as trusted peer on BSC
        receiver.setPeer(BSC_EID, escrowPeer);
        vm.stopPrank();

        vm.deal(user, 10 ether);
    }

    // ─── Receive Lock (mint) ───

    function test_lzReceive_mintsWrappedTokens() public {
        bytes memory lockPayload = abi.encode(user, OPINION_TOKEN_ID, uint256(1000));

        vm.prank(address(polyEndpoint));
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 1}),
            keccak256("guid"),
            lockPayload,
            address(0),
            ""
        );

        assertEq(wrappedToken.balanceOf(user, OPINION_TOKEN_ID), 1000);
        assertEq(receiver.totalBridged(OPINION_TOKEN_ID), 1000);
    }

    function test_lzReceive_multipleMintsAccumulate() public {
        bytes memory payload1 = abi.encode(user, OPINION_TOKEN_ID, uint256(500));
        bytes memory payload2 = abi.encode(user, OPINION_TOKEN_ID, uint256(300));

        vm.startPrank(address(polyEndpoint));
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 1}),
            keccak256("guid1"),
            payload1,
            address(0),
            ""
        );
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 2}),
            keccak256("guid2"),
            payload2,
            address(0),
            ""
        );
        vm.stopPrank();

        assertEq(wrappedToken.balanceOf(user, OPINION_TOKEN_ID), 800);
        assertEq(receiver.totalBridged(OPINION_TOKEN_ID), 800);
    }

    function test_lzReceive_differentRecipients() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        bytes memory payloadAlice = abi.encode(alice, OPINION_TOKEN_ID, uint256(600));
        bytes memory payloadBob = abi.encode(bob, OPINION_TOKEN_ID, uint256(400));

        vm.startPrank(address(polyEndpoint));
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 1}),
            keccak256("guid1"),
            payloadAlice,
            address(0),
            ""
        );
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 2}),
            keccak256("guid2"),
            payloadBob,
            address(0),
            ""
        );
        vm.stopPrank();

        assertEq(wrappedToken.balanceOf(alice, OPINION_TOKEN_ID), 600);
        assertEq(wrappedToken.balanceOf(bob, OPINION_TOKEN_ID), 400);
    }

    function test_lzReceive_revertNotEndpoint() public {
        bytes memory payload = abi.encode(user, OPINION_CONTRACT, OPINION_TOKEN_ID, uint256(100));

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OnlyEndpoint(address)", user));
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );
    }

    // ─── Bridge Back (burn + send unlock) ───

    function _mintWrappedTokens(address _to, uint256 _amount) internal {
        bytes memory lockPayload = abi.encode(_to, OPINION_TOKEN_ID, _amount);
        vm.prank(address(polyEndpoint));
        receiver.lzReceive(
            Origin({srcEid: BSC_EID, sender: escrowPeer, nonce: 1}),
            keccak256("guid"),
            lockPayload,
            address(0),
            ""
        );
    }

    function test_bridgeBack_success() public {
        _mintWrappedTokens(user, 1000);

        address bscRecipient = makeAddr("bscSafe");

        vm.prank(user);
        receiver.bridgeBack{value: 0.01 ether}(OPINION_TOKEN_ID, 400, bscRecipient, _option);

        // Wrapped tokens burned
        assertEq(wrappedToken.balanceOf(user, OPINION_TOKEN_ID), 600);
        assertEq(receiver.totalBridged(OPINION_TOKEN_ID), 600);

        // LZ message sent
        assertEq(polyEndpoint.messageCount(), 1);
    }

    function test_bridgeBack_messagePayload() public {
        _mintWrappedTokens(user, 1000);

        address bscRecipient = makeAddr("bscSafe");

        vm.prank(user);
        receiver.bridgeBack{value: 0.01 ether}(OPINION_TOKEN_ID, 500, bscRecipient, _option);

        MockEndpointV2.StoredMessage memory msg_ = polyEndpoint.lastMessage();
        assertEq(msg_.dstEid, BSC_EID);

        (address recipient, uint256 tokenId, uint256 amount) =
            abi.decode(msg_.message, (address, uint256, uint256));
        assertEq(recipient, bscRecipient);
        assertEq(tokenId, OPINION_TOKEN_ID);
        assertEq(amount, 500);
    }

    function test_bridgeBack_revertZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(BridgeReceiver.ZeroAmount.selector);
        receiver.bridgeBack{value: 0.01 ether}(OPINION_TOKEN_ID, 0, makeAddr("bsc"), _option);
    }

    function test_bridgeBack_revertZeroAddress() public {
        vm.prank(user);
        vm.expectRevert(BridgeReceiver.ZeroAddress.selector);
        receiver.bridgeBack{value: 0.01 ether}(OPINION_TOKEN_ID, 100, address(0), _option);
    }

    function test_bridgeBack_revertInsufficientBalance() public {
        _mintWrappedTokens(user, 100);

        vm.prank(user);
        vm.expectRevert(); // ERC1155 burn insufficient balance
        receiver.bridgeBack{value: 0.01 ether}(OPINION_TOKEN_ID, 200, makeAddr("bsc"), _option);
    }

    // ─── Config ───

    function test_setDstGasLimit() public {
        vm.prank(owner);
        receiver.setDstGasLimit(300_000);
        assertEq(receiver.dstGasLimit(), 300_000);
    }
}
