// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {OpinionEscrow} from "../src/OpinionEscrow.sol";
import {BridgeReceiver} from "../src/BridgeReceiver.sol";
import {WrappedOpinionToken} from "../src/WrappedOpinionToken.sol";
import {MockEndpointV2} from "./mocks/MockEndpointV2.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";

/// @title BridgeIntegrationTest
/// @notice Full end-to-end test simulating cross-chain bridge operations
///         between BSC (OpinionEscrow) and Polygon (BridgeReceiver).
///         Uses MockEndpointV2 to simulate LayerZero message delivery.
contract BridgeIntegrationTest is Test {
    // ─── Chain Constants ───
    uint32 constant BSC_EID = 30102;
    uint32 constant POLYGON_EID = 30109;

    // ─── BSC Contracts ───
    MockEndpointV2 public bscEndpoint;
    OpinionEscrow public escrow;
    MockERC1155 public opinionToken;

    // ─── Polygon Contracts ───
    MockEndpointV2 public polyEndpoint;
    BridgeReceiver public receiver;
    WrappedOpinionToken public wrappedToken;

    // ─── Actors ───
    address public deployer = makeAddr("deployer");
    address public alice = makeAddr("alice"); // EOA
    address public aliceBscSafe = makeAddr("aliceBscSafe");
    address public alicePolySafe = makeAddr("alicePolySafe");

        // options
    bytes public _option = abi.encodePacked(
        uint16(0x0003),
        uint8(0x01),
        uint16(0x0011),
        uint8(0x01),
        uint128(200_000)
    );

    uint256 constant TOKEN_ID_YES = 1;  // "Fed March - 25bps decrease - YES"
    uint256 constant TOKEN_ID_NO = 2;   // "Fed March - 25bps decrease - NO"

    function setUp() public {
        // ─── Deploy BSC Side ───
        bscEndpoint = new MockEndpointV2(BSC_EID);
        opinionToken = new MockERC1155();

        vm.prank(deployer);
        escrow = new OpinionEscrow(address(bscEndpoint), deployer, address(opinionToken), POLYGON_EID);

        // ─── Deploy Polygon Side ───
        polyEndpoint = new MockEndpointV2(POLYGON_EID);

        vm.startPrank(deployer);
        wrappedToken = new WrappedOpinionToken(deployer, address(opinionToken));
        receiver = new BridgeReceiver(address(polyEndpoint), deployer, address(wrappedToken), BSC_EID);

        // Configure permissions
        wrappedToken.setBridge(address(receiver));

        // Set peers (cross-chain trust)
        escrow.setPeer(POLYGON_EID, bytes32(uint256(uint160(address(receiver)))));
        receiver.setPeer(BSC_EID, bytes32(uint256(uint160(address(escrow)))));
        vm.stopPrank();

        // ─── Setup Alice ───
        // Mint Opinion tokens to Alice's BSC Safe (simulating her prediction market position)
        opinionToken.mint(aliceBscSafe, TOKEN_ID_YES, 5000);
        opinionToken.mint(aliceBscSafe, TOKEN_ID_NO, 3000);
        vm.deal(aliceBscSafe, 10 ether);
        vm.deal(alice, 10 ether);

    }

    // ═══════════════════════════════════════════════
    // Full Flow: Lock on BSC → Mint on Polygon
    // ═══════════════════════════════════════════════

    function test_fullFlow_lockAndMint() public {
        // Step 1: Alice's BSC Safe approves escrow
        vm.prank(aliceBscSafe);
        opinionToken.setApprovalForAll(address(escrow), true);

        // Step 2: Alice locks 2000 YES tokens from BSC Safe, wants them on her Polygon EOA
        vm.prank(aliceBscSafe);

        escrow.lock{value: 0.01 ether}(TOKEN_ID_YES, 2000, alice, _option);

        // Verify BSC state
        assertEq(opinionToken.balanceOf(aliceBscSafe, TOKEN_ID_YES), 3000); // 5000 - 2000
        assertEq(opinionToken.balanceOf(address(escrow), TOKEN_ID_YES), 2000);
        assertEq(escrow.totalLocked(TOKEN_ID_YES), 2000);

        // Step 3: Simulate LayerZero delivery to Polygon
        bscEndpoint.deliverMessage(0, polyEndpoint);

        // Verify Polygon state
        assertEq(wrappedToken.balanceOf(alice, TOKEN_ID_YES), 2000);
        assertEq(wrappedToken.totalSupply(TOKEN_ID_YES), 2000);
        assertEq(receiver.totalBridged(TOKEN_ID_YES), 2000);

    }

    // ═══════════════════════════════════════════════
    // Full Flow: Lock → Mint → Bridge Back → Unlock
    // ═══════════════════════════════════════════════

    function test_fullFlow_roundTrip() public {
        // ─── Phase 1: BSC → Polygon ───
        vm.prank(aliceBscSafe);
        opinionToken.setApprovalForAll(address(escrow), true);

        vm.prank(aliceBscSafe);
        escrow.lock{value: 0.01 ether}(TOKEN_ID_YES, 1000, alice, _option);

        // Deliver to Polygon
        bscEndpoint.deliverMessage(0, polyEndpoint);

        assertEq(wrappedToken.balanceOf(alice, TOKEN_ID_YES), 1000);

        // ─── Phase 2: Polygon → BSC (bridge back) ───
        // Alice bridges 600 wrapped tokens back to her BSC Safe
        vm.prank(alice);
        receiver.bridgeBack{value: 0.01 ether}(TOKEN_ID_YES, 600, aliceBscSafe, _option);

        // Verify Polygon: 400 remaining
        assertEq(wrappedToken.balanceOf(alice, TOKEN_ID_YES), 400);
        assertEq(wrappedToken.totalSupply(TOKEN_ID_YES), 400);

        // Deliver unlock message to BSC
        polyEndpoint.deliverMessage(0, bscEndpoint);

        // Verify BSC: Alice got 600 back, escrow still holds 400
        assertEq(opinionToken.balanceOf(aliceBscSafe, TOKEN_ID_YES), 4600); // 3000 + 600 (from remaining) + 1000 unlock
        // Wait, let me recalculate:
        // Started: 5000
        // Locked 1000 → balance 4000 (wait, we locked from aliceBscSafe)
        // After lock: aliceBscSafe has 4000, escrow has 1000
        // After unlock of 600: aliceBscSafe has 4600, escrow has 400
        assertEq(opinionToken.balanceOf(address(escrow), TOKEN_ID_YES), 400);
        assertEq(escrow.totalLocked(TOKEN_ID_YES), 400);
    }

    // ═══════════════════════════════════════════════
    // Full Flow: Complete round trip (lock all, return all)
    // ═══════════════════════════════════════════════

    function test_fullFlow_completeRoundTrip() public {
        vm.prank(aliceBscSafe);
        opinionToken.setApprovalForAll(address(escrow), true);

        // Lock 1000
        vm.prank(aliceBscSafe);
        escrow.lock{value: 0.01 ether}(TOKEN_ID_YES, 1000, alice, _option);
        bscEndpoint.deliverMessage(0, polyEndpoint);

        // Bridge back all 1000
        vm.prank(alice);
        receiver.bridgeBack{value: 0.01 ether}(TOKEN_ID_YES, 1000, aliceBscSafe, _option);
        polyEndpoint.deliverMessage(0, bscEndpoint);

        // Everything should be back to original state
        assertEq(opinionToken.balanceOf(aliceBscSafe, TOKEN_ID_YES), 5000);
        assertEq(opinionToken.balanceOf(address(escrow), TOKEN_ID_YES), 0);
        assertEq(wrappedToken.balanceOf(alice, TOKEN_ID_YES), 0);
        assertEq(wrappedToken.totalSupply(TOKEN_ID_YES), 0);
        assertEq(escrow.totalLocked(TOKEN_ID_YES), 0);
        assertEq(receiver.totalBridged(TOKEN_ID_YES), 0);
    }

    // ═══════════════════════════════════════════════
    // Multiple token types
    // ═══════════════════════════════════════════════

    function test_fullFlow_multipleTokenTypes() public {
        vm.prank(aliceBscSafe);
        opinionToken.setApprovalForAll(address(escrow), true);

        // Lock YES tokens
        vm.prank(aliceBscSafe);
        escrow.lock{value: 0.01 ether}(TOKEN_ID_YES, 2000, alice, _option);
        bscEndpoint.deliverMessage(0, polyEndpoint);

        // Lock NO tokens
        vm.prank(aliceBscSafe);
        escrow.lock{value: 0.01 ether}(TOKEN_ID_NO, 1500, alice, _option);
        bscEndpoint.deliverMessage(1, polyEndpoint);

        assertEq(wrappedToken.balanceOf(alice, TOKEN_ID_YES), 2000);
        assertEq(wrappedToken.balanceOf(alice, TOKEN_ID_NO), 1500);

        // Different wrapped token IDs
        assertNotEq(TOKEN_ID_YES, TOKEN_ID_NO);
    }

    // ═══════════════════════════════════════════════
    // Multiple users
    // ═══════════════════════════════════════════════

    function test_fullFlow_multipleUsers() public {
        address bob = makeAddr("bob");
        address bobBscSafe = makeAddr("bobBscSafe");
        opinionToken.mint(bobBscSafe, TOKEN_ID_YES, 3000);
        vm.deal(bobBscSafe, 10 ether);
        vm.deal(bob, 10 ether);

        // Both users approve
        vm.prank(aliceBscSafe);
        opinionToken.setApprovalForAll(address(escrow), true);
        vm.prank(bobBscSafe);
        opinionToken.setApprovalForAll(address(escrow), true);

        // Alice locks 1000
        vm.prank(aliceBscSafe);
        escrow.lock{value: 0.01 ether}(TOKEN_ID_YES, 1000, alice, _option);
        bscEndpoint.deliverMessage(0, polyEndpoint);

        // Bob locks 2000
        vm.prank(bobBscSafe);
        escrow.lock{value: 0.01 ether}(TOKEN_ID_YES, 2000, bob, _option);
        bscEndpoint.deliverMessage(1, polyEndpoint);

        // Verify individual balances on Polygon
        assertEq(wrappedToken.balanceOf(alice, TOKEN_ID_YES), 1000);
        assertEq(wrappedToken.balanceOf(bob, TOKEN_ID_YES), 2000);
        assertEq(wrappedToken.totalSupply(TOKEN_ID_YES), 3000);

        // Escrow holds 3000 total
        assertEq(opinionToken.balanceOf(address(escrow), TOKEN_ID_YES), 3000);
    }

    // ═══════════════════════════════════════════════
    // Edge case: bridge back to different BSC address
    // ═══════════════════════════════════════════════

    function test_bridgeBack_toDifferentAddress() public {
        vm.prank(aliceBscSafe);
        opinionToken.setApprovalForAll(address(escrow), true);

        vm.prank(aliceBscSafe);
        escrow.lock{value: 0.01 ether}(TOKEN_ID_YES, 1000, alice, _option);
        bscEndpoint.deliverMessage(0, polyEndpoint);

        // Alice bridges back to a completely different address (her EOA on BSC, or another wallet)
        address alternateRecipient = makeAddr("alternate");

        vm.prank(alice);
        receiver.bridgeBack{value: 0.01 ether}(TOKEN_ID_YES, 1000, alternateRecipient, _option);
        polyEndpoint.deliverMessage(0, bscEndpoint);

        // Tokens go to the specified recipient, not the original locker
        assertEq(opinionToken.balanceOf(alternateRecipient, TOKEN_ID_YES), 1000);
        assertEq(opinionToken.balanceOf(aliceBscSafe, TOKEN_ID_YES), 4000); // Unchanged
    }
}
