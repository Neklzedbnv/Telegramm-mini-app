# Telegramm-mini-app

# DeFi Super-App (Option A) — 4 Week Plan (Production-Grade, Fully Aligned)

## Overview

DeFi Super-App — это production-level децентрализованный протокол, полностью соответствующий требованиям курса Blockchain Technologies 2.

Проект включает:

- Lending Protocol (core primitive, с нуля)
- ERC-4626 Yield Vault
- DAO Governance (полный lifecycle)
- Chainlink Oracle (с защитой от устаревших данных)
- The Graph (индексация)
- L2 Deployment
- Полный testing + security + CI pipeline

---

## Tech Stack

### Smart Contracts

- Solidity + Foundry
- OpenZeppelin:
  - ERC20Votes + ERC20Permit
  - ERC4626
  - Governor + TimelockController
  - ReentrancyGuard
  - AccessControl
  - UUPSUpgradeable

### Infrastructure

- Chainlink (Price Feeds)
- The Graph (Subgraph)

### Frontend

- React + Tailwind
- Telegram Mini App SDK
- WalletConnect + MetaMask
- wagmi / viem

### Deployment

- Arbitrum Sepolia / Optimism Sepolia

---

## Architecture (Key Requirements Covered)

### 1. Upgradeability (UUPS Proxy)

- LendingPool реализован как upgradeable контракт (UUPS)
- Реализован upgrade path:
  - V1 → V2 (документирован)

---

### 2. Factory Pattern (CREATE + CREATE2)

- Factory контракт:
  - деплой LendingPool / Vault
  - CREATE (обычный)
  - CREATE2 (deterministic address)

---

### 3. Inline Assembly (Yul)

Используется для:

- оптимизации math операций
- gas reduction

---

### 4. Token Standards

- ERC20Votes (Governance Token)
- ERC4626 (Vault)
- ERC721 (минимальный NFT для выполнения требований)

---

### 5. DeFi Primitive

- Lending Protocol (реализован с нуля):
  - LTV
  - Health Factor
  - Liquidation

---

### 6. Oracle (Chainlink)

- Price Feed integration
- Staleness check:
  - revert если price устарел
- Mock oracle для тестов

---

### 7. Governance (Full Stack)

- Governor
- Timelock (2 days delay)
- ERC20Votes token

Полный flow:

- propose → vote → queue → execute

---

### 8. Layer 2

- Deployment:
  - Arbitrum Sepolia / Optimism Sepolia
- Gas comparison:
  - L1 vs L2 (таблица)

---

## Roles & Responsibilities

### Абзал — Smart Contracts

- Lending Protocol
- Liquidation
- ERC-4626 Vault
- Upgradeability (UUPS)
- Tests (unit + fuzz + invariant)

---

### Никита — Infrastructure / Governance

- Chainlink Oracle
- The Graph
- DAO (Governor + Timelock)
- Deployment + verification
- CI pipeline

---

### Арман — Frontend (TMA)

- Telegram Mini App
- Wallet (MetaMask + WalletConnect)
- UI / UX
- Subgraph integration

---

## Development Plan (4 Weeks)

---

## Week 1 — Core + Governance + Proxy

**Абзал:**

- ERC20Votes token
- Governor + Timelock

**Никита:**

- LendingPool (UUPS):
  - deposit / borrow / repay / withdraw
- Health Factor

**Арман:**

- TMA setup
- Wallet connection

---

## Week 2 — Security + Oracle + Factory

**Абзал:**

- Chainlink Oracle:
  - price feed
  - stale check
- Factory (CREATE + CREATE2)

**Никита:**

- liquidation()
- ReentrancyGuard
- CEI pattern

**Арман:**

- UI:
  - deposit / borrow / repay

---

## Week 3 — Vault + Testing + Subgraph

**Абзал:**

- Subgraph:
  - ≥4 entities
  - ≥5 queries

**Никита:**

- ERC-4626 Vault
- Vault → Lending integration

- Tests:
  - ≥50 unit
  - ≥10 fuzz
  - ≥5 invariant

**Арман:**

- Dashboard:
  - balances
  - health factor
  - yield

---

## Week 4 — Deployment + CI + Demo

**Абзал:**

- L2 deploy + verification
- Gas report (L1 vs L2)
- CI:
  - forge test
  - coverage
  - slither

**Никита:**

- Gas optimization
- Inline assembly optimization

**Арман:**

- Final UI
- Error handling
- Network detection

**Все:**

- End-to-end testing
- Demo

---

## Testing (STRICT REQUIREMENTS)

Согласно требованиям :

- ≥ 50 unit tests  
- ≥ 10 fuzz tests  
- ≥ 5 invariant tests  
- ≥ 3 fork tests  
- Coverage ≥ 90%  

---

## Security

- ReentrancyGuard / CEI
- AccessControl
- SafeERC20
- Slither:
  - 0 High
  - 0 Medium

### Vulnerability Case Studies

- Reentrancy attack (reproduced + fixed)
- Access control bug (reproduced + fixed)

---

## DevOps / CI

- GitHub Actions:
  - build
  - test
  - coverage
  - slither

- Lint:
  - forge fmt
  - solhint

---

## Frontend Requirements

- Wallet:
  - MetaMask (required)
  - WalletConnect

- Write functions:
  - deposit
  - borrow
  - vote

- Governance UI:
  - proposals
  - vote
  - status

- Data from The Graph

- Error handling:
  - wrong network
  - tx rejected
  - insufficient balance

---

## Data Flow

```

Smart Contracts
↓
Events
↓
The Graph
↓
Frontend (TMA)

```

---

## Design Patterns (Justified)

- UUPS Proxy → upgradeability
- Factory → scalable deployment
- CEI → security
- Access Control → permission safety
- Timelock → governance delay
- ReentrancyGuard → attack prevention

---

## Deliverables

Согласно требованиям :

- Smart contracts
- Full test suite
- Frontend
- Subgraph
- Deployment scripts
- Audit report (8+ pages)
- Architecture doc (6+ pages)
- Gas report
- README
- Slides

---

## Goal

Сделать:

- Production-grade DeFi protocol  
- Полное соответствие всем требованиям курса  
- Готовность к защите и сложному Q&A  

---

## Deployed Contracts — Arbitrum Sepolia (Chain ID: 421614)

> Last deployment: 2026-05-18. All contracts verified on [Arbiscan Sepolia](https://sepolia.arbiscan.io).

| Contract | Address | Explorer |
|---|---|---|
| MockOracle | `0x109cc51fd4d224683cbdab7b7214189c5321c518` | [View](https://sepolia.arbiscan.io/address/0x109cc51fd4d224683cbdab7b7214189c5321c518) |
| LendingPoolV1 (impl) | `0xbc1d5c56d3e6f27c5bd782daf10b7e4bfc89bdcf` | [View](https://sepolia.arbiscan.io/address/0xbc1d5c56d3e6f27c5bd782daf10b7e4bfc89bdcf) |
| LendingPool (proxy) | `0xbfb7281f1a0a23453dac651196274c6c9656ace0` | [View](https://sepolia.arbiscan.io/address/0xbfb7281f1a0a23453dac651196274c6c9656ace0) |
| YieldVault | `0x0c6b33a0923cf963e348f3840867728d806588af` | [View](https://sepolia.arbiscan.io/address/0x0c6b33a0923cf963e348f3840867728d806588af) |
| MockUSDC | `0x19dc4be2c07321bbe1360faa561cbe5900d93647` | [View](https://sepolia.arbiscan.io/address/0x19dc4be2c07321bbe1360faa561cbe5900d93647) |
| DeFiToken (DGT) | _redeploy pending_ | — |
| DeFiTimelock | _redeploy pending_ | — |
| DeFiGovernor | _redeploy pending_ | — |
| PositionNFT | _redeploy pending_ | — |
| PoolFactory | _redeploy pending_ | — |
| AMM | _redeploy pending_ | — |

> **Note:** Run `forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify` to deploy all contracts including AMM, governance, and factory. After deployment update addresses above and in `frontend/src/config/contracts.ts` and `subgraph/subgraph.yaml`.

---

# React + TypeScript + Vite

This template provides a minimal setup to get React working in Vite with HMR and some ESLint rules.

Currently, two official plugins are available:

- [@vitejs/plugin-react](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react) uses [Oxc](https://oxc.rs)
- [@vitejs/plugin-react-swc](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react-swc) uses [SWC](https://swc.rs/)
