// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OApp, Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OAppOptionsType3} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {WrappedOpinionToken} from "./WrappedOpinionToken.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// @title BridgeReceiver
/// @notice Deployed on Polygon. Receives lock confirmations from OpinionEscrow on BSC
///         and mints WrappedOpinionToken. Handles bridge-back requests by burning wrapped
///         tokens and sending unlock messages to BSC.
contract BridgeReceiver is OApp, OAppOptionsType3, Pausable {

    using SafeERC20 for IERC20;

    /// @notice The WrappedOpinionToken contract this bridge mints/burns.
    WrappedOpinionToken public immutable wrappedToken;

    /// @notice LayerZero endpoint ID for BSC (where OpinionEscrow lives).
    uint32 public immutable bscEid;

    /// @notice Default gas limit for execution on BSC side (unlock operation).
    uint128 public dstGasLimit = 500_000;

    /// @notice Msg type for sending a string, for use in OAppOptionsType3 as an enforced option
    uint16 public constant SEND = 1;

    /// @notice Total bridged per tokenId (safety invariant: should match WrappedOpinionToken supply).
    mapping(uint256 tokenId => uint256 amount) public totalBridged;

    error ZeroAmount();
    error ZeroAddress();
    error InsufficientBridgedBalance(uint256 tokenId, uint256 locked, uint256 requested);
    error CannotRescueLockedTokens(uint256 tokenId);

    event BridgedIn(
        address indexed polygonRecipient,
        uint256 indexed tokenId,
        uint256 amount
    );
    event BridgedBack(
        address indexed polygonSender,
        address indexed bscRecipient,
        uint256 tokenId,
        uint256 amount
    );
    event DstGasLimitSet(uint128 gasLimit);

    event TokensRescued(address indexed token, uint256 indexed tokenId, uint256 amount, address indexed to);


    /// @param _endpoint LayerZero endpoint address on Polygon.
    /// @param _owner Contract owner (team multisig).
    /// @param _wrappedToken Address of the WrappedOpinionToken contract.
    /// @param _bscEid LayerZero endpoint ID for BSC.
    constructor(
        address _endpoint,
        address _owner,
        address _wrappedToken,
        uint32 _bscEid
    ) OApp(_endpoint, _owner) Ownable(_owner) {
        wrappedToken = WrappedOpinionToken(_wrappedToken);
        bscEid = _bscEid;
    }

    // ─── Admin ───

    function setDstGasLimit(uint128 _gasLimit) external onlyOwner {
        dstGasLimit = _gasLimit;
        emit DstGasLimitSet(_gasLimit);
    }

    function pause() external onlyOwner { _pause(); }

    function unpause() external onlyOwner { _unpause(); }

    // ─── Receive Lock Confirmation (BSC → Polygon) ───

    function _lzReceive(
        Origin calldata, /* _origin */
        bytes32, /* _guid */
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal override {
        (address polygonRecipient, uint256 tokenId, uint256 amount) =
            abi.decode(_message, (address, uint256, uint256));

        totalBridged[tokenId] += amount;
        wrappedToken.mint(polygonRecipient, tokenId, amount);

        emit BridgedIn(polygonRecipient, tokenId, amount);
    }

    // ─── Bridge Back (Polygon → BSC) ───

    function bridgeBack(
        uint256 _tokenId,
        uint256 _amount,
        address _bscRecipient,
        bytes calldata _options
    ) external payable whenNotPaused returns (MessagingReceipt memory receipt) {
        if (_amount == 0) revert ZeroAmount();
        if (_bscRecipient == address(0)) revert ZeroAddress();

        if (totalBridged[_tokenId] < _amount) revert InsufficientBridgedBalance(_tokenId, totalBridged[_tokenId], _amount);

        totalBridged[_tokenId] -= _amount;
        wrappedToken.burn(msg.sender, _tokenId, _amount);

        bytes memory payload = abi.encode(_bscRecipient, _tokenId, _amount);
        receipt = _lzSend(bscEid, payload, combineOptions(bscEid, SEND, _options), MessagingFee(msg.value, 0), payable(msg.sender));

        emit BridgedBack(msg.sender, _bscRecipient, _tokenId, _amount);
    }

    function quoteBridgeBackFee(
        uint256 _tokenId,
        uint256 _amount,
        address _bscRecipient,
        bytes calldata _options
    ) public view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(_bscRecipient, _tokenId, _amount);
        fee = _quote(bscEid, payload, combineOptions(bscEid, SEND, _options), false);
    }

    // ─── Rescue ───

    function rescueTokens(
        address _token,
        uint256 _tokenId,
        uint256 _amount,
        address _to
    ) external onlyOwner {
            if (_to == address(0)) revert ZeroAddress();
        if (_token == address(wrappedToken) && totalBridged[_tokenId] > 0)
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

}