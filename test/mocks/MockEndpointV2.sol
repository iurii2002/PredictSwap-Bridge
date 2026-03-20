// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

import {ILayerZeroEndpointV2, MessagingParams, MessagingReceipt, MessagingFee, Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {ILayerZeroReceiver} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroReceiver.sol";

/// @title MockEndpointV2
/// @notice Simulates a LayerZero V2 endpoint for local testing.
///         Stores sent messages and provides a helper to manually deliver them
///         to the destination receiver, simulating cross-chain message passing.
contract MockEndpointV2 is ILayerZeroEndpointV2 {
    uint32 public immutable eid; // This endpoint's chain ID

    struct StoredMessage {
        uint32 dstEid;
        bytes32 receiver;
        bytes message;
        bytes options;
        address sender;
    }

    StoredMessage[] public messages;
    mapping(uint32 dstEid => mapping(bytes32 receiver => uint64 nonce)) public outboundNonces;

    constructor(uint32 _eid) {
        eid = _eid;
    }

    // ─── ILayerZeroEndpointV2 ───

    function send(MessagingParams calldata _params, address _refundAddress)
        external
        payable
        override
        returns (MessagingReceipt memory receipt)
    {
        uint64 nonce = ++outboundNonces[_params.dstEid][_params.receiver];

        messages.push(StoredMessage({
            dstEid: _params.dstEid,
            receiver: _params.receiver,
            message: _params.message,
            options: _params.options,
            sender: msg.sender
        }));

        receipt = MessagingReceipt({
            guid: keccak256(abi.encodePacked(nonce, _params.dstEid, _params.receiver)),
            nonce: nonce,
            fee: MessagingFee(msg.value, 0)
        });
    }

    function quote(MessagingParams calldata, address) external pure override returns (MessagingFee memory) {
        // Return a small fixed fee for testing
        return MessagingFee(0.001 ether, 0);
    }

    function setDelegate(address) external override {
        // No-op in mock
    }

    // ─── Test Helpers ───

    /// @notice Get the number of messages sent through this endpoint.
    function messageCount() external view returns (uint256) {
        return messages.length;
    }

    /// @notice Get the last sent message.
    function lastMessage() external view returns (StoredMessage memory) {
        require(messages.length > 0, "No messages");
        return messages[messages.length - 1];
    }

    /// @notice Deliver a stored message to its destination receiver.
    ///         Simulates the LayerZero DVN verification and executor delivery.
    /// @param _msgIndex Index of the message in the messages array.
    /// @param _dstEndpoint The mock endpoint on the "destination chain" (used to derive srcEid).
    function deliverMessage(uint256 _msgIndex, MockEndpointV2 _dstEndpoint) external {
        StoredMessage memory msg_ = messages[_msgIndex];

        address receiver = address(uint160(uint256(msg_.receiver)));
        uint64 nonce = outboundNonces[msg_.dstEid][msg_.receiver];

        Origin memory origin = Origin({
            srcEid: eid,
            sender: bytes32(uint256(uint160(msg_.sender))),
            nonce: nonce
        });

        bytes32 guid = keccak256(abi.encodePacked(nonce, msg_.dstEid, msg_.receiver));

        // Call lzReceive on the destination, pretending to be the destination endpoint
        // We need to call from the destination endpoint address
        _dstEndpoint.executeDelivery(receiver, origin, guid, msg_.message);
    }

    /// @notice Execute message delivery. Called by the source endpoint's deliverMessage.
    ///         This function calls lzReceive on the target from this endpoint's address.
    function executeDelivery(
        address _receiver,
        Origin memory _origin,
        bytes32 _guid,
        bytes memory _message
    ) external {
        ILayerZeroReceiver(_receiver).lzReceive(_origin, _guid, _message, address(this), "");
    }

    /// @notice Direct delivery helper — manually specify all parameters.
    ///         Useful for testing error cases or custom scenarios.
    function directDeliver(
        address _receiver,
        uint32 _srcEid,
        address _sender,
        uint64 _nonce,
        bytes calldata _message
    ) external {
        Origin memory origin = Origin({
            srcEid: _srcEid,
            sender: bytes32(uint256(uint160(_sender))),
            nonce: _nonce
        });
        bytes32 guid = keccak256(abi.encodePacked(_nonce, _srcEid));
        ILayerZeroReceiver(_receiver).lzReceive(origin, guid, _message, address(this), "");
    }

    // Add these stubs at the bottom of MockEndpointV2, before closing brace

function verify(Origin calldata, address, bytes32) external override {}
function verifiable(Origin calldata, address) external pure override returns (bool) { return false; }
function initializable(Origin calldata, address) external pure override returns (bool) { return false; }
function lzReceive(Origin calldata, address, bytes32, bytes calldata, bytes calldata) external payable override {}
function clear(address, Origin calldata, bytes32, bytes calldata) external override {}
function setLzToken(address) external override {}
function lzToken() external pure override returns (address) { return address(0); }
function nativeToken() external pure override returns (address) { return address(0); }
function skip(address, uint32, bytes32, uint64) external override {}
function nilify(address, uint32, bytes32, uint64, bytes32) external override {}
function burn(address, uint32, bytes32, uint64, bytes32) external override {}
function nextGuid(address, uint32, bytes32) external pure override returns (bytes32) { return bytes32(0); }
function inboundNonce(address, uint32, bytes32) external pure override returns (uint64) { return 0; }
function outboundNonce(address _sender, uint32 _dstEid, bytes32 _receiver) external view override returns (uint64) { return outboundNonces[_dstEid][_receiver]; }
function inboundPayloadHash(address, uint32, bytes32, uint64) external pure override returns (bytes32) { return bytes32(0); }
function lazyInboundNonce(address, uint32, bytes32) external pure override returns (uint64) { return 0; }
function executable(Origin calldata, address) external pure returns (uint8) { return 0; }
function getSendContext() external pure override returns (uint32, address) { return (0, address(0)); }
function isSendingMessage() external pure override returns (bool) { return false; }
function getRegisteredLibraries() external pure override returns (address[] memory) { return new address[](0); }
function isRegisteredLibrary(address) external pure override returns (bool) { return false; }
function registerLibrary(address) external override {}
function isDefaultSendLibrary(address, uint32) external pure override returns (bool) { return false; }
function defaultSendLibrary(uint32) external pure override returns (address) { return address(0); }
function setDefaultSendLibrary(uint32, address) external override {}
function getSendLibrary(address, uint32) external pure override returns (address) { return address(0); }
function setSendLibrary(address, uint32, address) external override {}
function defaultReceiveLibrary(uint32) external pure override returns (address) { return address(0); }
function setDefaultReceiveLibrary(uint32, address, uint256) external override {}
function defaultReceiveLibraryTimeout(uint32) external pure override returns (address, uint256) { return (address(0), 0); }
function setDefaultReceiveLibraryTimeout(uint32, address, uint256) external override {}
function getReceiveLibrary(address, uint32) external pure override returns (address, bool) { return (address(0), false); }
function setReceiveLibrary(address, uint32, address, uint256) external override {}
function receiveLibraryTimeout(address, uint32) external pure override returns (address, uint256) { return (address(0), 0); }
function setReceiveLibraryTimeout(address, uint32, address, uint256) external override {}
function isSupportedEid(uint32) external pure override returns (bool) { return true; }
function isValidReceiveLibrary(address, uint32, address) external pure override returns (bool) { return false; }
function setConfig(address, address, SetConfigParam[] calldata) external override {}
function getConfig(address, address, uint32, uint32) external pure override returns (bytes memory) { return ""; }
function composeQueue(address, address, bytes32, uint16) external pure override returns (bytes32) { return bytes32(0); }
function sendCompose(address, bytes32, uint16, bytes calldata) external override {}
function lzCompose(address, address, bytes32, uint16, bytes calldata, bytes calldata) external payable override {}
}
