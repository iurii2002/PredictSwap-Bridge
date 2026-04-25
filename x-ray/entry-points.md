# Entry Point Map

> PredictSwap Bridge | 16 entry points | 2 permissionless | 2 role-gated | 12 admin-only

---

## Protocol Flow Paths

### Setup (Owner)

`deploy PredictionMarketEscrow` → `deploy WrappedPredictionToken` → `deploy BridgeReceiver` → `WrappedPredictionToken.setBridge()` → `PredictionMarketEscrow.setPeer()` → `BridgeReceiver.setPeer()` → `setDstGasLimit()` (both) → `unpause()` (both)

### User Flow — Bridge In

`[owner setup above]` → `PredictionMarketEscrow.lock()`  ◄── user must hold & approve ERC-1155
                              └─→ LZ message → `BridgeReceiver._lzReceive()` → `WrappedPredictionToken.mint()`

### User Flow — Bridge Back

`[bridge-in above]` → `BridgeReceiver.bridgeBack()`  ◄── user must hold wrapped tokens
                              └─→ LZ message → `PredictionMarketEscrow._lzReceive()` → `IERC1155.safeTransferFrom()`

### Emergency (Owner)

`[any state]` → `pause()` (stops lock/bridgeBack, NOT _lzReceive)
             → `rescueTokens()` / `rescueERC20()` / `rescueETH()`  ◄── only when totalLocked/totalBridged == 0 for tokenId

---

## Permissionless

### `PredictionMarketEscrow.lock()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, whenNotPaused, nonReentrant |
| Caller | User (BSC token holder) |
| Parameters | _tokenId (user-controlled), _amount (user-controlled), _polygonRecipient (user-controlled), _options (user-controlled) |
| Call chain | → `IERC1155.safeTransferFrom(user → escrow)` → `_lzSend()` → LZ endpoint |
| State modified | `totalLocked[_tokenId] += _amount` |
| Value flow | ERC-1155 tokens: user → escrow; native: user → LZ endpoint (messaging fee) |
| Reentrancy guard | yes |

### `BridgeReceiver.bridgeBack()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, whenNotPaused, nonReentrant |
| Caller | User (Polygon wrapped token holder) |
| Parameters | _tokenId (user-controlled), _amount (user-controlled), _bscRecipient (user-controlled), _options (user-controlled) |
| Call chain | → `WrappedPredictionToken.burn(msg.sender)` → `_lzSend()` → LZ endpoint |
| State modified | `totalBridged[_tokenId] -= _amount` |
| Value flow | Wrapped tokens: burned from user; native: user → LZ endpoint (messaging fee) |
| Reentrancy guard | yes |

---

## Role-Gated

### `onlyBridge` (BridgeReceiver address)

#### `WrappedPredictionToken.mint()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, onlyBridge |
| Caller | BridgeReceiver (via _lzReceive) |
| Parameters | _to (protocol-derived from LZ message), _tokenId (protocol-derived), _amount (protocol-derived) |
| Call chain | → `ERC1155._mint()` |
| State modified | `totalSupply[_tokenId] += _amount`, `balanceOf[_to][_tokenId] += _amount` |
| Value flow | Mints wrapped ERC-1155 to recipient |
| Reentrancy guard | no (caller has nonReentrant) |

#### `WrappedPredictionToken.burn()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, onlyBridge |
| Caller | BridgeReceiver (via bridgeBack) |
| Parameters | _from (protocol-derived: msg.sender of bridgeBack), _tokenId (user-controlled), _amount (user-controlled) |
| Call chain | → `ERC1155._burn()` |
| State modified | `totalSupply[_tokenId] -= _amount`, `balanceOf[_from][_tokenId] -= _amount` |
| Value flow | Burns wrapped ERC-1155 from holder |
| Reentrancy guard | no (caller has nonReentrant) |

---

## Admin-Only

| Contract | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| WrappedPredictionToken | `setBridge(_bridge)` | address (one-shot) | `bridge` — permanently set |
| BridgeReceiver | `pause()` | none | `_paused = true` |
| BridgeReceiver | `unpause()` | none | `_paused = false` |
| BridgeReceiver | `setDstGasLimit(_gasLimit)` | uint128 | `dstGasLimit`, enforced options |
| BridgeReceiver | `setPeer(eid, peer)` | uint32, bytes32 | `peers[eid]` |
| BridgeReceiver | `rescueTokens(token, id, amount, to)` | address, uint256, uint256, address | external ERC-1155 transfer |
| BridgeReceiver | `rescueERC20(token, amount, to)` | address, uint256, address | external ERC-20 transfer |
| BridgeReceiver | `rescueETH(to)` | address payable | native ETH transfer |
| PredictionMarketEscrow | `pause()` | none | `_paused = true` |
| PredictionMarketEscrow | `unpause()` | none | `_paused = false` |
| PredictionMarketEscrow | `setDstGasLimit(_gasLimit)` | uint128 | `dstGasLimit`, enforced options |
| PredictionMarketEscrow | `setPeer(eid, peer)` | uint32, bytes32 | `peers[eid]` |
| PredictionMarketEscrow | `rescueTokens(token, id, amount, to)` | address, uint256, uint256, address | external ERC-1155 transfer |
| PredictionMarketEscrow | `rescueERC20(token, amount, to)` | address, uint256, address | external ERC-20 transfer |
| PredictionMarketEscrow | `rescueETH(to)` | address payable | native ETH transfer |
