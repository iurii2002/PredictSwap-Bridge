# X-Ray Report

> PredictSwap Bridge | 298 nSLOC | 0e580e0 (`main`) | Foundry | 25/04/26

---

## 1. Protocol Overview

**What it does:** Cross-chain ERC-1155 bridge that locks prediction market shares on BSC and mints 1:1 wrapped equivalents on Polygon via LayerZero V2 messaging.

- **Users**: Prediction market traders who want to use BSC-native ERC-1155 shares on Polygon (e.g. in SwapPool)
- **Core flow**: Lock ERC-1155 on BSC → LZ message → mint WrappedPredictionToken on Polygon; reverse to bridge back
- **Key mechanism**: Lock/mint + burn/unlock pattern via LayerZero V2 OApp cross-chain messaging
- **Token model**: WrappedPredictionToken (ERC-1155) — 1:1 backed by locked shares in PredictionMarketEscrow
- **Admin model**: Single `owner` (intended multisig) controls pause, setPeer, setDstGasLimit, rescue functions — no timelock

For a visual overview of the protocol's architecture, see the [architecture diagram](architecture.svg).

### Contracts in Scope

| Subsystem | Key Contracts | nSLOC | Role |
|-----------|--------------|------:|------|
| BSC Escrow | PredictionMarketEscrow | 132 | Lock ERC-1155 shares on BSC, send/receive LZ messages |
| Polygon Bridge | BridgeReceiver | 124 | Receive LZ messages, mint/burn wrapped tokens, bridge back |
| Wrapped Token | WrappedPredictionToken | 42 | ERC-1155 wrapped representation, bridge-only mint/burn |

### How It Fits Together

The core trick: Lock original tokens on Chain A, send a message to Chain B confirming the lock, and mint wrapped equivalents — reverse the process to bridge back.

### Bridge In (BSC → Polygon)

```
User on BSC
 └─ PredictionMarketEscrow.lock()                      *pausable, nonReentrant*
     ├─ totalLocked[tokenId] += amount                  *state update before transfer*
     ├─ IERC1155.safeTransferFrom(user → escrow)        *pulls ERC-1155 from user*
     └─ _lzSend() → LayerZero V2 endpoint
                      └─ BridgeReceiver._lzReceive()    *on Polygon, via LZ endpoint*
                          ├─ totalBridged[tokenId] += amount
                          └─ WrappedPredictionToken.mint(recipient, tokenId, amount)
```

### Bridge Back (Polygon → BSC)

```
User on Polygon
 └─ BridgeReceiver.bridgeBack()                         *pausable, nonReentrant*
     ├─ totalBridged[tokenId] -= amount
     ├─ WrappedPredictionToken.burn(msg.sender, tokenId, amount)
     └─ _lzSend() → LayerZero V2 endpoint
                      └─ PredictionMarketEscrow._lzReceive()   *on BSC, via LZ endpoint*
                          ├─ totalLocked[tokenId] -= amount
                          └─ IERC1155.safeTransferFrom(escrow → bscRecipient)
```

---

## 2. Threat & Trust Model

> Protocol classified as: **Bridge** — lock/mint + burn/unlock pattern with LayerZero V2 cross-chain messaging

### Actors & Adversary Model

| Actor | Trust Level | Capabilities |
|-------|-------------|-------------|
| Owner | Trusted | All admin functions instant: setPeer (redirect messages), pause/unpause, setDstGasLimit, rescue ETH/ERC20/ERC1155. No timelock. |
| Bridge (BridgeReceiver) | Bounded (set once, immutable) | mint/burn on WrappedPredictionToken — only address authorized by one-shot setBridge latch |
| LZ Endpoint | Bounded (peer-verified) | Delivers cross-chain messages — OApp base enforces `peers[srcEid]` check before `_lzReceive` executes |
| User | Untrusted | lock() on BSC, bridgeBack() on Polygon — all user inputs validated |

**Adversary Ranking** (ordered by threat for bridge type):

1. **Compromised owner** — instant setPeer can redirect all cross-chain messages to attacker-controlled contract; rescue functions can drain non-locked assets.
2. **LayerZero relay/DVN compromise** — forged cross-chain messages could mint unbacked wrapped tokens or unlock tokens without corresponding burns.
3. **ERC-1155 callback attacker** — `safeTransferFrom` triggers `onERC1155Received` on recipient; a reverting recipient permanently blocks the LZ unlock message.
4. **Malicious `_bscRecipient` setter** — user-controlled address in `bridgeBack()` flows to `safeTransferFrom` on BSC; non-IERC1155Receiver contract permanently strands funds.

See [entry-points.md](entry-points.md) for the full permissionless entry point map.

### Trust Boundaries

- **Owner → Protocol** — no timelock; worst instant action: `setPeer` to redirect all cross-chain messages to attacker contract, effectively stealing all future locks/unlocks. `BridgeReceiver.sol:142`, `PredictionMarketEscrow.sol:130`.

- **LZ Endpoint → _lzReceive** — OApp peer check gates all inbound messages; if LZ endpoint is compromised or peer misconfigured, arbitrary minting/unlocking is possible. `BridgeReceiver.sol:177`, `PredictionMarketEscrow.sol:213`.

- **BridgeReceiver → WrappedPredictionToken** — one-shot `setBridge` latch; once set, only BridgeReceiver can mint/burn. `WrappedPredictionToken.sol:86-91`.

### Key Attack Surfaces

- **Owner compromise — instant setPeer and rescue** — `PredictionMarketEscrow.sol:130` / `BridgeReceiver.sol:142` — owner can instantly redirect all cross-chain message routing via `setPeer` and drain non-locked assets via rescue functions; worth confirming whether team multisig setup is enforced off-chain.

- **Non-IERC1155Receiver as bridgeBack recipient** &nbsp;&#91;[X-1](invariants.md#x-1)&#93; — `BridgeReceiver.sol:219` burns wrapped tokens atomically before LZ delivery; if `_bscRecipient` on BSC is a contract without `onERC1155Received`, the `safeTransferFrom` in `PredictionMarketEscrow._lzReceive:226` permanently reverts — worth tracing the full LZ retry path and confirming whether stuck funds can be recovered.

- **Asymmetric pause leaves _lzReceive open** &nbsp;&#91;[I-3](invariants.md#i-3)&#93; — `BridgeReceiver.sol:177` / `PredictionMarketEscrow.sol:213` — `_lzReceive` is intentionally not pausable (documented design); during a security incident, owner cannot halt incoming mints/unlocks without calling `setPeer(eid, bytes32(0))` which is irreversible.

- **Coarse rescue guard blocks surplus recovery** &nbsp;&#91;[G-7](invariants.md#g-7), [G-14](invariants.md#g-14)&#93; — `PredictionMarketEscrow.sol:248` / `BridgeReceiver.sol:261` — binary `totalLocked > 0` / `totalBridged > 0` gate prevents rescuing excess tokens sent directly (not via lock/bridgeBack) for any tokenId with active locks.

- **Cross-chain state commitment before delivery confirmation** &nbsp;&#91;[X-2](invariants.md#x-2)&#93; — `PredictionMarketEscrow.sol:178-182` / `BridgeReceiver.sol:218-222` — both `lock()` and `bridgeBack()` commit state (lock tokens / burn tokens) before the LZ message is confirmed delivered on the remote chain; worth confirming LayerZero retry semantics cover permanent failure scenarios.

### Protocol-Type Concerns

**As a Bridge:**
- **No per-message or per-window rate limits** — `BridgeReceiver._lzReceive:187` / `PredictionMarketEscrow._lzReceive:225` — unlimited minting/unlocking per message; a compromised peer can drain in a single transaction. Pause is the only circuit breaker and it doesn't gate `_lzReceive`.
- **No admin recovery for permanently failed LZ messages** — no `emergencyRemint` or `emergencyUnlock` function exists; if a bridge-back LZ message permanently fails on BSC (e.g. paused prediction market contract), user funds are irrecoverably lost.

### Temporal Risk Profile

**Deployment & Initialization:**
- Both contracts start paused (`_pause()` in constructors) — `PredictionMarketEscrow.sol:123`, `BridgeReceiver.sol:135`. Multi-step setup (setPeer, setDstGasLimit, setBridge, unpause) requires careful ordering; front-running risk mitigated by pause gate.
- `setBridge` is one-shot latch — `WrappedPredictionToken.sol:88` — if called with wrong address before ownership transfer, bridge is permanently misconfigured.

### Composability & Dependency Risks

**Dependency Risk Map:**

> **LayerZero V2** — via `PredictionMarketEscrow._lzSend()`, `BridgeReceiver._lzReceive()`
> - Assumes: messages are delivered exactly once, peer verification is sound
> - Validates: OApp base checks `peers[srcEid]` on every inbound message
> - Mutability: LZ endpoint is upgradeable by LayerZero governance
> - On failure: LZ stores failed messages for retry; permanent failure = stuck funds

> **Prediction Market ERC-1155** — via `PredictionMarketEscrow.lock()`, `PredictionMarketEscrow._lzReceive()`
> - Assumes: standard ERC-1155 transfer behavior (exact amounts, no fees)
> - Validates: NONE — no post-transfer balance check
> - Mutability: external contract, immutable reference in escrow
> - On failure: safeTransferFrom revert causes entire tx or LZ message to fail

**Token Assumptions** (unvalidated):
- Prediction Market ERC-1155: assumes no fee-on-transfer, no rebasing, standard `safeTransferFrom` behavior — `PredictionMarketEscrow.sol:179` records `_amount` in `totalLocked` before transfer, not actual received amount.

---

## 3. Invariants

> ### Full invariant map: **[invariants.md](invariants.md)**
>
> A dedicated reference file contains the complete invariant analysis — do not look here for the catalog.
>
> - **14 Enforced Guards** (`G-1` … `G-14`) — per-call preconditions with `Check` / `Location` / `Purpose`
> - **5 Single-Contract Invariants** (`I-1` … `I-5`) — Conservation, Bound, StateMachine
> - **2 Cross-Contract Invariants** (`X-1` … `X-2`) — caller/callee pairs that cross scope boundaries
> - **2 Economic Invariants** (`E-1` … `E-2`) — higher-order properties deriving from `I-N` + `X-N`
>
> Every inferred block cites a concrete Δ-pair, guard-lift + write-sites, state edge, temporal predicate, or NatSpec quote. The **On-chain=No** blocks are the high-signal ones — each is simultaneously an invariant and a potential bug. Attack-surface bullets above cross-link directly into the relevant blocks (e.g. `[X-1]`, `[I-3]`).

---

## 4. Documentation Quality

| Aspect | Status | Notes |
|--------|--------|-------|
| README | Present | `README.md` — architecture, deployment, usage |
| NatSpec | ~3 annotations | Good coverage on all public functions; 3 explicit invariant comments |
| Spec/Whitepaper | Missing | No formal specification beyond README |
| Inline Comments | Thorough | Detailed NatSpec on every function, deployment checklists in contract headers |

---

## 5. Test Analysis

| Metric | Value | Source |
|--------|-------|--------|
| Test files | 7 | File scan |
| Test functions | 86 | File scan |
| Line coverage | BridgeReceiver 60%, Escrow 61%, Wrapped 100% | forge coverage |
| Branch coverage | BridgeReceiver 30%, Escrow 30%, Wrapped 86% | forge coverage |

### Test Depth

| Category | Count | Contracts Covered |
|----------|-------|-------------------|
| Unit | 52 | BridgeReceiver, PredictionMarketEscrow, WrappedPredictionToken |
| Integration | 8 | Full round-trip (BridgeIntegration) |
| Stateless Fuzz | 34 | All 3 contracts + integration |
| Stateful Fuzz (Foundry) | 0 | none |
| Formal Verification (Certora) | 0 | none |
| Formal Verification (Halmos) | 0 | none |

### Gaps

- **No stateful fuzz (invariant) tests** — the documented invariant `totalBridged[id] == totalSupply[id]` is ideal for invariant testing but untested with foundry invariant harness.
- **No formal verification** — integer arithmetic is simple (add/sub only) but cross-chain conservation properties would benefit from formal proof.
- **Branch coverage ~30% on bridge contracts** — rescue functions and edge cases in `_lzReceive` appear under-tested.
- **No fork tests** — real LZ endpoint behavior not tested.

---

## 6. Developer & Git History

> Repo shape: normal_dev — 13 commits over 27 days from a single developer, 6 touching source files. Analyzed branch: `main` at `0e580e0`.

### Contributors

| Author | Commits | Source Lines (+/-) | % of Source Changes |
|--------|--------:|--------------------|--------------------:|
| Iurii | 13 | +1101 / -394 | 100% |

### Review & Process Signals

| Signal | Value | Assessment |
|--------|-------|------------|
| Unique contributors | 1 | Single developer |
| Merge commits | 1 of 13 (8%) | No peer review signals |
| Repo age | 2026-03-20 → 2026-04-16 | 27 days |
| Recent source activity (30d) | 5 commits | Active |
| Test co-change rate | 50% | Half of source commits also modify tests |

### File Hotspots

| File | Modifications | Note |
|------|-------------:|------|
| src/BridgeReceiver.sol | 4 | High churn — core bridge logic |
| src/PredictionMarketEscrow.sol | 4 | High churn — core escrow logic |
| src/WrappedPredictionToken.sol | 2 | Moderate — renamed from WrappedOpinionToken |

### Security-Relevant Commits

| SHA | Date | Subject | Score | Key Signal |
|-----|------|---------|------:|------------|
| 5715f1e | 2026-03-20 | first commit | 17 | Initial deployment — adds guards, access control, fund flows |
| 90d3795 | 2026-04-07 | added reentrancy guard | 16 | Explicit security fix — adds nonReentrant to _lzReceive |
| 82b4dfc | 2026-04-07 | updated dstGasSet function | 15 | Rewrites guards, access control |
| 0e580e0 | 2026-04-16 | pashov skill findings updated | 14 | Loosens access control — net code removal |

### Dangerous Area Evolution

| Security Area | Commits | Key Files |
|--------------|--------:|-----------|
| access_control | 4 | BridgeReceiver.sol |
| fund_flows | 4 | BridgeReceiver.sol |
| signatures | 4 | BridgeReceiver.sol |
| state_machines | 4 | BridgeReceiver.sol |

### Security Observations

- **100% single-developer** — Iurii authored all 13 commits; no peer review evidence.
- **Reentrancy guard was added post-initial-commit** — `90d3795` explicitly adds `nonReentrant` to `_lzReceive`; pre-guard code existed for 18 days.
- **BridgeReceiver.sol is the #1 hotspot** — 4 modifications across all 4 security domains.
- **50% fix-without-test rate** — half of security-relevant source changes lack corresponding test updates.
- **Late PredictFunEscrow addition** — `0e580e0` and `44cea07` touch a now-removed `PredictFunEscrow.sol` with no tests.

### Cross-Reference Synthesis

- **BridgeReceiver.sol is #1 in BOTH churn AND attack-surface priority** — all top surfaces (setPeer, _lzReceive pause gap, bridgeBack recipient) route through it.
- **Reentrancy guard commit (90d3795) had no test changes** — the fix was applied without verifying reentrancy protection via tests; fuzz tests added later partially cover this.
- **NatSpec invariant `totalBridged == totalSupply` at BridgeReceiver.sol:38 aligns with I-1** — explicitly documented but not enforced by stateful fuzz or formal verification.

---

## X-Ray Verdict

**ADEQUATE** — well-structured 298 nSLOC bridge with clear access controls, thorough NatSpec, and 86 test functions including 34 fuzz tests, but no timelock on admin operations and no stateful invariant or formal verification testing.

**Structural facts:**
1. 298 nSLOC across 3 contracts on 2 chains — small, focused scope
2. Single developer (100% of commits) with no merge-based review signals
3. Owner has instant control over setPeer, pause, rescue with no timelock or multisig enforcement on-chain
4. 86 test functions (52 unit + 34 stateless fuzz) but 0 stateful invariant tests and 0 formal verification
5. Branch coverage at ~30% for bridge contracts indicates rescue and edge-case paths are under-tested
