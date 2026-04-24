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
- LendingPool (UUPS):
  - deposit / borrow / repay / withdraw
- Health Factor

**Никита:**
- ERC20Votes token
- Governor + Timelock

**Арман:**
- TMA setup
- Wallet connection

---

## Week 2 — Security + Oracle + Factory

**Абзал:**
- liquidation()
- ReentrancyGuard
- CEI pattern

**Никита:**
- Chainlink Oracle:
  - price feed
  - stale check
- Factory (CREATE + CREATE2)

**Арман:**
- UI:
  - deposit / borrow / repay

---

## Week 3 — Vault + Testing + Subgraph

**Абзал:**
- ERC-4626 Vault
- Vault → Lending integration

- Tests:
  - ≥50 unit
  - ≥10 fuzz
  - ≥5 invariant

**Никита:**
- Subgraph:
  - ≥4 entities
  - ≥5 queries

**Арман:**
- Dashboard:
  - balances
  - health factor
  - yield

---

## Week 4 — Deployment + CI + Demo

**Абзал:**
- Gas optimization
- Inline assembly optimization

**Никита:**
- L2 deploy + verification
- Gas report (L1 vs L2)
- CI:
  - forge test
  - coverage
  - slither

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
```
