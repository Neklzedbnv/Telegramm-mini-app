# DeFi Protocol — Documented GraphQL Queries

## Q1 — User deposit history
```graphql
query UserDeposits($user: Bytes!) {
  deposits(where: { user: $user }, orderBy: blockTimestamp, orderDirection: desc) {
    id
    token
    amount
    blockTimestamp
    transactionHash
  }
}
```

## Q2 — User borrow history
```graphql
query UserBorrows($user: Bytes!) {
  borrows(where: { user: $user }, orderBy: blockTimestamp, orderDirection: desc) {
    id
    token
    amount
    blockTimestamp
    transactionHash
  }
}
```

## Q3 — User aggregated position
```graphql
query UserPosition($user: Bytes!) {
  userPosition(id: $user) {
    totalDeposited
    totalBorrowed
    totalRepaid
    liquidationCount
    lastActivityTimestamp
  }
}
```

## Q4 — Recent liquidations (last 10)
```graphql
query RecentLiquidations {
  liquidations(orderBy: blockTimestamp, orderDirection: desc, first: 10) {
    liquidator
    borrower
    collateralToken
    debtToken
    debtRepaid
    collateralSeized
    blockTimestamp
    transactionHash
  }
}
```

## Q5 — All repayments for a token
```graphql
query RepaysByToken($token: Bytes!) {
  repays(where: { token: $token }, orderBy: blockTimestamp, orderDirection: desc) {
    user
    amount
    blockTimestamp
    transactionHash
  }
}
```

## Q6 — Recent AMM swaps (last 20)
```graphql
query RecentSwaps {
  swaps(orderBy: blockTimestamp, orderDirection: desc, first: 20) {
    sender
    tokenIn
    amountIn
    tokenOut
    amountOut
    blockTimestamp
    transactionHash
  }
}
```

## Q7 — AMM liquidity events for a provider
```graphql
query ProviderLiquidity($provider: Bytes!) {
  liquidityAddeds(where: { provider: $provider }, orderBy: blockTimestamp, orderDirection: desc) {
    amountA
    amountB
    shares
    blockTimestamp
  }
  liquidityRemoveds(where: { provider: $provider }, orderBy: blockTimestamp, orderDirection: desc) {
    amountA
    amountB
    shares
    blockTimestamp
  }
}
```

## Q8 — AMM protocol stats (total swaps + volume)
```graphql
query AMMStats {
  ammStats(id: "0x616d6d") {
    totalSwaps
    totalVolumeTokenA
    totalVolumeTokenB
    lastUpdatedTimestamp
  }
}
```
