// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {OApp, Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OAppOptionsType3} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title OpinionEscrow
/// @notice Deployed on BSC. Locks Opinion ERC-1155 shares in escrow and sends a LayerZero
///         message to BridgeReceiver on Polygon, which mints wrapped tokens.
///         Receives unlock messages from Polygon to release shares back to users.
/// @dev Handles a single Opinion ERC-1155 contract (set as immutable).
///      If Opinion deploys a new contract, deploy a new OpinionEscrow.
contract OpinionEscrow is OApp, OAppOptionsType3, IERC1155Receiver, Pausable {

    using SafeERC20 for IERC20;

    /// @notice The Opinion ERC-1155 contract this escrow handles.
    address public immutable opinionContract;

    /// @notice LayerZero endpoint ID for the Polygon chain (where BridgeReceiver lives).
    uint32 public immutable polygonEid;

    /// @notice Total locked per tokenId across all users.
    mapping(uint256 tokenId => uint256 amount) public totalLocked;

    /// @notice Default gas limit for execution on Polygon side.
    uint128 public dstGasLimit = 500_000;

    /// @notice Msg type for sending a string, for use in OAppOptionsType3 as an enforced option
    uint16 public constant SEND = 1;

    error ZeroAmount();
    error ZeroAddress();
    error InsufficientLockedBalance(uint256 tokenId, uint256 locked, uint256 requested);
    error CannotRescueLockedTokens(uint256 tokenId);

    event Locked(
        address indexed user,
        uint256 indexed tokenId,
        uint256 amount,
        address polygonRecipient
    );
    event Unlocked(address indexed user, uint256 indexed tokenId, uint256 amount);
    event DstGasLimitSet(uint128 gasLimit);

    event TokensRescued(address indexed token, uint256 indexed tokenId, uint256 amount, address indexed to);


    /// @param _endpoint LayerZero endpoint address on BSC.
    /// @param _owner Contract owner (team multisig).
    /// @param _opinionContract The Opinion ERC-1155 contract address on BSC.
    /// @param _polygonEid LayerZero endpoint ID for Polygon.
    constructor(
        address _endpoint,
        address _owner,
        address _opinionContract,
        uint32 _polygonEid
    ) OApp(_endpoint, _owner) Ownable(_owner) {
        if (_opinionContract == address(0)) revert ZeroAddress();
        opinionContract = _opinionContract;
        polygonEid = _polygonEid;
    }

    // ─── Admin ───

    function pause() external onlyOwner { _pause(); }

    function unpause() external onlyOwner { _unpause(); }

    function setDstGasLimit(uint128 _gasLimit) external onlyOwner {
        dstGasLimit = _gasLimit;
        emit DstGasLimitSet(_gasLimit);
    }

    // ─── Lock (BSC → Polygon) ───

    function lock(
        uint256 _tokenId,
        uint256 _amount,
        address _polygonRecipient,
        bytes calldata _options
    ) external payable whenNotPaused returns (MessagingReceipt memory receipt) {
        if (_amount == 0) revert ZeroAmount();
        if (_polygonRecipient == address(0)) revert ZeroAddress();

        totalLocked[_tokenId] += _amount;
        IERC1155(opinionContract).safeTransferFrom(msg.sender, address(this), _tokenId, _amount, "");

        bytes memory payload = abi.encode(_polygonRecipient, _tokenId, _amount);
        receipt = _lzSend(polygonEid, payload, combineOptions(polygonEid, SEND, _options), MessagingFee(msg.value, 0), payable(msg.sender));

        emit Locked(msg.sender, _tokenId, _amount, _polygonRecipient);
    }

    function quoteLockFee(
        uint256 _tokenId,
        uint256 _amount,
        address _polygonRecipient,
        bytes calldata _options
    ) public view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(_polygonRecipient, _tokenId, _amount);
        fee = _quote(polygonEid, payload, combineOptions(polygonEid, SEND, _options), false);
    }

    // ─── Unlock (Polygon → BSC) ───

    function _lzReceive(
        Origin calldata, /* _origin */
        bytes32, /* _guid */
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal override {
        (address bscRecipient, uint256 tokenId, uint256 amount) =
            abi.decode(_message, (address, uint256, uint256));

        if (totalLocked[tokenId] < amount) revert InsufficientLockedBalance(tokenId, totalLocked[tokenId], amount);

        totalLocked[tokenId] -= amount;

        IERC1155(opinionContract).safeTransferFrom(address(this), bscRecipient, tokenId, amount, "");

        emit Unlocked(bscRecipient, tokenId, amount);
    }

    // ─── Rescue ───

    function rescueTokens(
        address _token,
        uint256 _tokenId,
        uint256 _amount,
        address _to
    ) external onlyOwner {
        if (_to == address(0)) revert ZeroAddress();
        if (_token == opinionContract && totalLocked[_tokenId] > 0)
            revert CannotRescueLockedTokens(_tokenId);
        IERC1155(_token).safeTransferFrom(address(this), _to, _tokenId, _amount, "");
        emit TokensRescued(_token, _tokenId, _amount, _to);
    }

    function rescueERC20(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOwner {
        if (_to == address(0)) revert ZeroAddress();
        IERC20(_token).safeTransfer(_to, _amount);
        emit TokensRescued(_token, 0, _amount, _to);
    }

    function rescueETH(address payable _to) external onlyOwner {
        if (_to == address(0)) revert ZeroAddress();
        uint256 balance = address(this).balance;
        (bool ok,) = _to.call{value: balance}("");
        require(ok, "ETH transfer failed");        
        emit TokensRescued(address(0), 0, balance, _to);
    }

    receive() external payable {}

    // ─── ERC1155 Receiver ───

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}