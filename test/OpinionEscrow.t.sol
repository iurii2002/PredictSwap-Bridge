// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {OpinionEscrow} from "../src/OpinionEscrow.sol";
import {MockEndpointV2} from "./mocks/MockEndpointV2.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

contract OpinionEscrowTest is Test {
    OpinionEscrow public escrow;
    MockEndpointV2 public bscEndpoint;
    MockERC1155 public opinionToken;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public opinionContract = makeAddr("opinionContract");
    address public polygonRecipient = makeAddr("polygonRecipient");
    address public bridgeReceiver = makeAddr("bridgeReceiver");

        // options
    bytes public _option = abi.encodePacked(
        uint16(0x0003),
        uint8(0x01),
        uint16(0x0011),
        uint8(0x01),
        uint128(200_000)
    );

    uint32 constant BSC_EID = 30102;
    uint32 constant POLYGON_EID = 30109;
    uint256 constant TOKEN_ID = 1;
    bytes32 bridgeReceiverPeer;

    function setUp() public {
        bscEndpoint = new MockEndpointV2(BSC_EID);
        opinionToken = new MockERC1155();

        // Precompute peer value before any pranks
        // Deploy escrow first with no prank, then compute
        vm.startPrank(owner);
        escrow = new OpinionEscrow(address(bscEndpoint), owner, address(opinionToken), POLYGON_EID);
        bridgeReceiverPeer = bytes32(uint256(uint160(bridgeReceiver)));
        escrow.setPeer(POLYGON_EID, bridgeReceiverPeer);
        vm.stopPrank();

        // Fund user with tokens and ETH for gas
        opinionToken.mint(user, TOKEN_ID, 10_000);
        vm.deal(user, 10 ether);
    }

    // ─── Lock ───

    function test_lock_success() public {
        vm.startPrank(user);
        opinionToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 1000, polygonRecipient, _option);
        vm.stopPrank();

        // Tokens transferred to escrow
        assertEq(opinionToken.balanceOf(address(escrow), TOKEN_ID), 1000);
        assertEq(opinionToken.balanceOf(user, TOKEN_ID), 9000);

        // Accounting updated
        assertEq(escrow.totalLocked(TOKEN_ID), 1000);

        // LZ message sent
        assertEq(bscEndpoint.messageCount(), 1);
    }

    function test_lock_messagePayload() public {
        vm.startPrank(user);
        opinionToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 500, polygonRecipient, _option);
        vm.stopPrank();

        MockEndpointV2.StoredMessage memory msg_ = bscEndpoint.lastMessage();
        assertEq(msg_.dstEid, POLYGON_EID);
        assertEq(msg_.sender, address(escrow));

        // Decode payload
        (address recipient, uint256 tokenId, uint256 amount) =
            abi.decode(msg_.message, (address, uint256, uint256));
        assertEq(recipient, polygonRecipient);
        assertEq(tokenId, TOKEN_ID);
        assertEq(amount, 500);
    }

    function test_lock_multipleLocks() public {
        vm.startPrank(user);
        opinionToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 300, polygonRecipient, _option);
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 700, polygonRecipient, _option);
        vm.stopPrank();

        assertEq(escrow.totalLocked(TOKEN_ID), 1000);
        assertEq(bscEndpoint.messageCount(), 2);
    }

    function test_lock_revertZeroAmount() public {
        vm.startPrank(user);
        opinionToken.setApprovalForAll(address(escrow), true);
        vm.expectRevert(OpinionEscrow.ZeroAmount.selector);
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 0, polygonRecipient, _option);
        vm.stopPrank();
    }

    function test_lock_revertNoApproval() public {
        vm.prank(user);
        vm.expectRevert(); // ERC1155: caller is not token owner or approved
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 100, polygonRecipient, _option);
    }

    function test_lock_revertInsufficientBalance() public {
        vm.startPrank(user);
        opinionToken.setApprovalForAll(address(escrow), true);
        vm.expectRevert(); // ERC1155: insufficient balance
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 99_999, polygonRecipient, _option);
        vm.stopPrank();
    }

    // ─── Unlock (via LZ receive) ───

    function test_unlock_success() public {
        // First lock some tokens
        vm.startPrank(user);
        opinionToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 1000, polygonRecipient, _option);
        vm.stopPrank();

        // Simulate unlock message from BridgeReceiver on Polygon
        bytes memory unlockPayload = abi.encode(user, TOKEN_ID, uint256(600));

        vm.prank(address(bscEndpoint));
        escrow.lzReceive(
            Origin({srcEid: POLYGON_EID, sender: bridgeReceiverPeer, nonce: 1}),
            keccak256("guid"),
            unlockPayload,
            address(0),
            ""
        );

        // Tokens released
        assertEq(opinionToken.balanceOf(user, TOKEN_ID), 9600); // 9000 + 600
        assertEq(opinionToken.balanceOf(address(escrow), TOKEN_ID), 400);
        assertEq(escrow.totalLocked(TOKEN_ID), 400);
    }

    function test_unlock_toDifferentAddress() public {
        vm.startPrank(user);
        opinionToken.setApprovalForAll(address(escrow), true);
        escrow.lock{value: 0.01 ether}(TOKEN_ID, 1000, polygonRecipient, _option);
        vm.stopPrank();

        address bscRecipient = makeAddr("bscRecipient");

        bytes memory unlockPayload = abi.encode(bscRecipient, TOKEN_ID, uint256(1000));

        vm.prank(address(bscEndpoint));
        escrow.lzReceive(
            Origin({srcEid: POLYGON_EID, sender: bridgeReceiverPeer, nonce: 1}),
            keccak256("guid"),
            unlockPayload,
            address(0),
            ""
        );

        assertEq(opinionToken.balanceOf(bscRecipient, TOKEN_ID), 1000);
    }

    function test_unlock_revertNotEndpoint() public {
        bytes memory payload = abi.encode(user, address(opinionToken), TOKEN_ID, uint256(100));

        vm.prank(user); // Not the endpoint
        vm.expectRevert(abi.encodeWithSignature("OnlyEndpoint(address)", user));
        escrow.lzReceive(
            Origin({srcEid: POLYGON_EID, sender: bridgeReceiverPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );
    }

    function test_unlock_revertNotPeer() public {
        bytes memory payload = abi.encode(user, address(opinionToken), TOKEN_ID, uint256(100));

        vm.prank(address(bscEndpoint));
        vm.expectRevert(); // OnlyPeer
        escrow.lzReceive(
            Origin({srcEid: POLYGON_EID, sender: bridgeReceiverPeer, nonce: 1}),
            keccak256("guid"),
            payload,
            address(0),
            ""
        );
    }

    // ─── Config ───

    function test_setDstGasLimit() public {
        vm.prank(owner);
        escrow.setDstGasLimit(300_000);
        assertEq(escrow.dstGasLimit(), 300_000);
    }

    function test_setDstGasLimit_revertNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        escrow.setDstGasLimit(300_000);
    }

    // ─── ERC1155 Receiver ───

    function test_supportsInterface() public view {
        assertTrue(escrow.supportsInterface(0x4e2312e0)); // IERC1155Receiver
        assertTrue(escrow.supportsInterface(0x01ffc9a7)); // IERC165
    }
}
