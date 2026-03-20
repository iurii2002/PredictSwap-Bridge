// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title WrappedOpinionToken
/// @notice ERC-1155 wrapped representation of Opinion prediction market shares on Polygon.
///         Each tokenId is derived from the original Opinion contract address and tokenId,
///         ensuring uniqueness across different Opinion ERC-1155 contracts.
///         1:1 backed by locked shares in OpinionEscrow on BSC.
/// @dev Only the authorized bridge (BridgeReceiver) can mint and burn tokens.
contract WrappedOpinionToken is ERC1155, Ownable {
    /// @notice The BridgeReceiver contract authorized to mint/burn.
    address public bridge;

    /// @notice The Opinion ERC-1155 contract address on BSC that this token wraps.
    address public immutable opinionContract;


    /// @notice Total supply per tokenId (for pool accounting).
    mapping(uint256 tokenId => uint256 supply) public totalSupply;

    error OnlyBridge();
    error ZeroAddress();
    error ZeroAmount();
    error BridgeAlreadySet();

    event BridgeSet(address indexed bridge);
    
    modifier onlyBridge() {
        if (msg.sender != bridge) revert OnlyBridge();
        _;
    }

    /// @param _owner Contract owner (team multisig).
    /// @param _opinionContract The Opinion ERC-1155 contract address on BSC.
    constructor(address _owner, address _opinionContract) ERC1155("") Ownable(_owner) {
        if (_opinionContract == address(0)) revert ZeroAddress();
        opinionContract = _opinionContract;
    }

    // ─── Admin ───

    /// @notice Set the BridgeReceiver contract address. Only callable by owner.
    /// @param _bridge Address of the BridgeReceiver contract.
    function setBridge(address _bridge) external onlyOwner {
        if (_bridge == address(0)) revert ZeroAddress();
        if (bridge != address(0)) revert BridgeAlreadySet();
        bridge = _bridge;
        emit BridgeSet(_bridge);
    }

    // ─── Mint / Burn (Bridge Only) ───

    /// @notice Mint wrapped tokens. Called by BridgeReceiver when Opinion shares are locked on BSC.
    /// @param _to Recipient address on Polygon.
    /// @param _tokenId Opinion tokenId (used directly as wrappedTokenId).
    /// @param _amount Number of tokens to mint.
    function mint(
        address _to,
        uint256 _tokenId,
        uint256 _amount
    ) external onlyBridge {
        if (_to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();

        totalSupply[_tokenId] += _amount;
        _mint(_to, _tokenId, _amount, "");
    }

    /// @notice Burn wrapped tokens. Called by BridgeReceiver when user bridges back to BSC.
    /// @param _from Address whose tokens are burned.
    /// @param _tokenId The tokenId to burn.
    /// @param _amount Number of tokens to burn.
    function burn(address _from, uint256 _tokenId, uint256 _amount) external onlyBridge {
        if (_amount == 0) revert ZeroAmount();
        totalSupply[_tokenId] -= _amount;
        _burn(_from, _tokenId, _amount);
    }
}
