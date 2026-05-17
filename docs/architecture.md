# Architecture & Design Document

## DeFi Super-App — Telegram Mini App Protocol

**Network:** Arbitrum Sepolia  

---

## 1. System Context (C4 Level 1)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        EXTERNAL ACTORS                              │
│                                                                     │
│  [Telegram User]  ──browser──►  [Telegram Mini App (React/Vite)]   │
│                                         │                           │
│  [Token Holder]   ──wallet──►  [WalletConnect / MetaMask]          │
│                                         │                           │
│  [Liquidator Bot] ──script──►  [Arbitrum Sepolia RPC]              │
└─────────────────────────────────────────────────────────────────────┘
                                          │
                    ┌─────────────────────▼──────────────────────┐
                    │        DeFi Super-App Protocol              │
                    │   (smart contracts on Arbitrum Sepolia)     │
                    └───────────────────────────────────┬─────────┘
                                                        │
         ┌──────────────────────────────────────────────▼────────────┐
         │                  EXTERNAL SERVICES                        │
         │                                                           │
         │  [Chainlink Price Feeds]  [The Graph Subgraph]            │
         │  [Arbiscan Block Explorer]  [IPFS / Static Assets]        │
         └───────────────────────────────────────────────────────────┘
```

### Actors

| Actor | Description |
|---|---|
| Telegram User | Interacts via Mini App embedded in Telegram; connects wallet via WalletConnect |
| Token Holder | DGT governance token holder; may delegate, propose, and vote |
| Liquidator Bot | Off-chain keeper monitoring health factors; calls `liquidate()` when HF < 1.0 |
| Chainlink | Provides tamper-resistant on-chain price feeds for collateral valuation |
| The Graph | Indexes protocol events for fast off-chain queries (deposits, borrows, liquidations) |

---

## 2. Container / Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     SMART CONTRACT LAYER (Arbitrum Sepolia)             │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                     GOVERNANCE SUBSYSTEM                        │   │
│  │                                                                  │   │
│  │  DeFiToken (ERC20Votes + ERC20Permit)                           │   │
│  │       │ votes                                                    │   │
│  │       ▼                                                          │   │
│  │  DeFiGovernor ──propose/vote/queue/execute──► DeFiTimelock      │   │
│  │  (Governor + Settings + Counting + Timelock)   (2-day delay)    │   │
│  │                                        │owns                    │   │
│  └────────────────────────────────────────┼─────────────────────────┘  │
│                                           │                             │
│  ┌────────────────────────────────────────▼─────────────────────────┐  │
│  │                     CORE PROTOCOL                                │  │
│  │                                                                  │  │
│  │  ERC1967Proxy ──delegatecall──► LendingPoolV1 (impl)            │  │
│  │                                    │                             │  │
│  │  Can upgrade to ──────────────► LendingPoolV2 (flash loans)     │  │
│  │                                    │                             │  │
│  │  PoolFactory  ─CREATE/CREATE2──► LendingPoolV1 instances        │  │
│  └────────────────────────────────────┼─────────────────────────────┘  │
│                                       │                                 │
│  ┌────────────────────────────────────▼─────────────────────────────┐  │
│  │                      ORACLE LAYER                                │  │
│  │                                                                  │  │
│  │  IOracle ◄── ChainlinkOracleAdapter ──► Chainlink AggregatorV3  │  │
│  │           ◄── MockOracle (tests only)                            │  │
│  │                                                                  │  │
│  │  OracleLib (staleness check, WAD normalization, inline assembly) │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    VAULT & TOKENS                                │  │
│  │                                                                  │  │
│  │  YieldVault (ERC4626) ──deployToPool──► LendingPool             │  │
│  │  PositionNFT (ERC721 soulbound) ─mint on deposit─► User         │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

### Access Control Roles

| Role | Contract | Holder | Capabilities |
|---|---|---|---|
| `owner` | LendingPoolV1 | DeFiTimelock | addSupportedToken, setOracle, setPositionNFT, upgrade |
| `owner` | DeFiToken | DeFiTimelock | mint (capped at 100M) |
| `DEFAULT_ADMIN_ROLE` | DeFiTimelock | — (renounced after setup) | Manage Timelock roles |
| `PROPOSER_ROLE` | DeFiTimelock | DeFiGovernor | Schedule operations |
| `CANCELLER_ROLE` | DeFiTimelock | DeFiGovernor | Cancel scheduled operations |
| `EXECUTOR_ROLE` | DeFiTimelock | `address(0)` (anyone) | Execute after delay passes |
| `DEFAULT_ADMIN_ROLE` | YieldVault | deployer | Pause/unpause |
| `MANAGER_ROLE` | YieldVault | deployer | deployToPool, recallFromPool, accrueYield |

---

## 3. Proxy Layout & Storage Collision Analysis

### ERC1967 Proxy + UUPS

```
ERC1967Proxy
├── storage slot 0x360894... → implementation address (LendingPoolV1 or LendingPoolV2)
└── delegatecall → LendingPoolV1 storage layout (below)
```

### LendingPoolV1 Storage Layout

| Slot | Variable | Type | Notes |
|---|---|---|---|
| 0 | `_initialized` / `_initializing` | uint8 | OZ Initializable |
| 1 | `_owner` | address | OwnableUpgradeable |
| 2 | `__gap[0..48]` | uint256[49] | OZ gaps |
| 51 | `oracle` | address | IOracle |
| 52 | `positionNFT` | address | PositionNFT |
| 53 | `_collateral` | mapping(addr→mapping(addr→uint256)) | |
| 54 | `_debt` | mapping(addr→mapping(addr→uint256)) | |
| 55 | `_accruedInterest` | mapping(addr→mapping(addr→uint256)) | **added in V1.1** |
| 56 | `_lastAccrual` | mapping(addr→mapping(addr→uint256)) | **added in V1.1** |
| 57 | `totalDeposits` | mapping(addr→uint256) | |
| 58 | `totalBorrows` | mapping(addr→uint256) | |
| 59 | `supportedTokens` | mapping(addr→bool) | |
| 60 | `tokenList` | address[] | |

### LendingPoolV2 Additional Storage

| Slot | Variable | Type |
|---|---|---|
| 61 | `flashLoanFeeBps` | uint256 |
| 62 | `flashLoanFees` | mapping(address→uint256) |

**Storage collision proof:** V2 only appends new variables after all V1 slots. The `reinitializer(2)` guard prevents re-initialization. OpenZeppelin's upgrade safety check (`forge inspect --storage-layout`) confirms no overlaps.

---

## 4. Sequence Diagrams

### 4.1 Deposit → Borrow → Liquidate

```
User              LendingPool (proxy)         Oracle          PositionNFT
 │                      │                       │                  │
 │──deposit(TKN, 100)──►│                       │                  │
 │                      │──getPrice(TKN)────────►│                  │
 │                      │◄──────price────────────│                  │
 │                      │ _collateral += 100     │                  │
 │                      │──mint(user)────────────────────────────►  │
 │◄──Deposited event────│                       │                  │
 │                      │                       │                  │
 │──borrow(TKN, 70)────►│                       │                  │
 │                      │ _accrueInterest()      │                  │
 │                      │ _debt += 70            │                  │
 │                      │──_computeHealthFactor()│                  │
 │                      │  hf = 80*100/70 = 1.14 │                  │
 │◄──Borrowed event─────│                       │                  │
 │                      │                       │                  │
 │    [price drops]     │                       │                  │
 │                      │                       │                  │
Liquidator              │                       │                  │
 │──liquidate(user,TKN,TKN,70)─────────────────►│                  │
 │                      │──getPrice(TKN)────────►│                  │
 │                      │  hf = 80*80/70 = 0.91  │  (< 1.0)         │
 │                      │ _debt -= 70            │                  │
 │                      │ _collateral -= 73.5    │  (+5% bonus)     │
 │◄──collateral sent────│                       │                  │
 │◄──Liquidated event───│                       │                  │
```

### 4.2 Governance: Propose → Vote → Queue → Execute

```
Proposer         DeFiGovernor       DeFiTimelock      Target Contract
   │                  │                  │                  │
   │──propose()──────►│                  │                  │
   │                  │ state=Pending    │                  │
   │  [7200 blocks]   │                  │                  │
   │                  │ state=Active     │                  │
   │──castVote(1)────►│                  │                  │
   │  [50400 blocks]  │                  │                  │
   │                  │ state=Succeeded  │                  │
   │──queue()────────►│──schedule()─────►│                  │
   │                  │ state=Queued     │ (starts 2d timer)│
   │  [2 days]        │                  │                  │
   │──execute()──────►│──execute()──────►│──call()─────────►│
   │                  │ state=Executed   │                  │
```

### 4.3 ERC4626 Vault Deposit → Deploy to Pool

```
User             YieldVault          LendingPool
 │                  │                    │
 │──deposit(100)───►│                    │
 │                  │ shares = 100*1e18  │
 │◄──shares minted──│                    │
 │                  │                    │
 Manager            │                    │
 │──deployToPool(80)►│                   │
 │                  │──approve(pool,80)──►│
 │                  │──deposit(TKN,80)───►│
 │                  │ deployedAssets=80  │
 │◄──deployed event─│                   │
```

---

## 5. Data Model

### LendingPoolV1 State

```solidity
// Cross-collateral position tracking
mapping(address user => mapping(address token => uint256)) _collateral;
mapping(address user => mapping(address token => uint256)) _debt;
mapping(address user => mapping(address token => uint256)) _accruedInterest;
mapping(address user => mapping(address token => uint256)) _lastAccrual;

// Protocol-level aggregates
mapping(address token => uint256) totalDeposits;
mapping(address token => uint256) totalBorrows;
mapping(address token => bool)    supportedTokens;
address[] tokenList;
```

### Health Factor Formula

```
HF = (Σ collateral_i × price_i × LIQUIDATION_THRESHOLD/100) / (Σ debt_i × price_i)
   where LIQUIDATION_THRESHOLD = 80, PRECISION = 1e18

Implemented in inline assembly:
  weightedCollateral = totalCollateralValue * 80 / 100
  hf = weightedCollateral * PRECISION / totalDebtValue
```

### Interest Accrual (Linear, 5% APR)

```
accruedInterest += principal × INTEREST_RATE_BPS × elapsed / (10_000 × SECONDS_PER_YEAR)
```

Called on every `borrow`, `repay`, `liquidate` before state changes.

### YieldVault (ERC4626)

```
totalAssets() = token.balanceOf(address(this)) + accruedYield + deployedAssets
sharePrice   = totalAssets() / totalSupply()  (WAD precision)
```

---

## 6. Trust Assumptions

| Assumption | Risk if violated |
|---|---|
| DeFiTimelock owner = Governor only | Admin could bypass governance and call `schedule()` directly |
| Chainlink feeds are live and honest | Stale/manipulated prices → bad liquidations or protocol insolvency |
| Deployer renounces TimeLock admin | Deployer could grant roles to malicious contracts |
| YieldVault MANAGER_ROLE is trusted | Manager can drain `deployedAssets` via `recallFromLendingPool` |
| PositionNFT owner = LendingPool | Rogue owner could mint/burn NFTs to arbitrary users |

### What Timelock Controls

- `addSupportedToken` — can list malicious tokens to manipulate health factors
- `setOracle` — can point to a malicious oracle returning arbitrary prices
- `mint` (DeFiToken) — can inflate supply (capped at 100M)
- `upgradeToAndCall` — can replace the LendingPool implementation

### What Happens if Multisig is Compromised

If the deployer key is compromised before `renounceRole` is called: attacker can grant themselves `PROPOSER_ROLE` on the Timelock and schedule arbitrary calls with 2-day delay. The community has 2 days to notice and cancel via governance. After renouncement, no such risk exists.

---

## 7. Design Decisions Log (ADR)

### ADR-01: UUPS over Transparent Proxy

- **Context:** Need upgradeability for the lending pool without permanent admin overhead.
- **Options:** Transparent Proxy, UUPS, Beacon Proxy.
- **Decision:** UUPS — saves ~2,300 gas per call (no admin check in proxy), upgrade logic in implementation.
- **Consequences:** Incorrect upgrade can brick the proxy; mitigated by `_disableInitializers()` in constructor.

### ADR-02: Cross-collateral over Per-pair Pools

- **Context:** Users should be able to deposit multiple tokens as collateral.
- **Options:** Per-pair isolated pools (Aave v1), shared cross-collateral pool.
- **Decision:** Cross-collateral — simpler UX; health factor loops over all tokens.
- **Consequences:** O(n) gas per operation where n = number of supported tokens; acceptable for testnet.

### ADR-03: Soulbound PositionNFT

- **Context:** ERC-721 required; must be meaningful, not a cosmetic checkbox.
- **Options:** Transferable receipt NFT, soulbound position NFT.
- **Decision:** Soulbound — prevents selling "positions" separately from underlying collateral which would enable health factor manipulation.
- **Consequences:** Cannot be used as collateral in other protocols; NFT marketplaces cannot trade it.

### ADR-04: Linear Interest Rate

- **Context:** Need a documented interest rate model.
- **Options:** Linear (constant APR), utilization-based kinked rate (Compound/Aave).
- **Decision:** Linear 5% APR for simplicity and auditability; can be replaced in V3.
- **Consequences:** Under-prices risk at high utilization; acceptable for academic scope.

### ADR-05: Inline Assembly for Health Factor

- **Context:** Health factor computed on every borrow, withdraw, and liquidation.
- **Options:** Pure Solidity division, inline Yul assembly.
- **Decision:** Inline assembly to eliminate redundant safety checks on known-safe operands.
- **Consequences:** Less readable; benchmarked to save ~200 gas per call (see gas-report.md).

### ADR-06: Governor + Timelock Architecture

- **Context:** Governance required; must prevent flash-loan voting attacks.
- **Options:** Snapshot off-chain, on-chain Governor without timelock, Governor + Timelock.
- **Decision:** Governor + TimelockController — ERC20Votes uses past-block checkpoints eliminating flash-loan attacks; 2-day delay allows community reaction before execution.
- **Consequences:** Slow governance (minimum 1+7+2 = 10 days end-to-end); acceptable for protocol safety.
