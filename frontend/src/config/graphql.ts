import { request, gql } from 'graphql-request'

// Тестовый Endpoint сабграфа (замени на актуальный URL твоего сабграфа в The Graph)
const SUBGRAPH_URL = 'https://api.studio.thegraph.com/query/1753457/lending-pool-subgraph/v0.0.1'

// GraphQL Query для получения последних 5 депозитов пользователя
export const GET_USER_DEPOSITS = gql`
  query GetUserDeposits($user: Bytes!) {
    deposits(first: 5, orderBy: blockTimestamp, orderDirection: desc, where: { user: $user }) {
      id
      amount
      token
      blockTimestamp
      transactionHash
    }
    borrows(first: 5, orderBy: blockTimestamp, orderDirection: desc, where: { user: $user }) {
      id
      amount
      token
      blockTimestamp
      transactionHash
    }
    repays(first: 5, orderBy: blockTimestamp, orderDirection: desc, where: { user: $user }) {
      id
      amount
      token
      blockTimestamp
      transactionHash
    }
    swaps(first: 5, orderBy: blockTimestamp, orderDirection: desc, where: { sender: $user }) {
      id
      amountIn
      amountOut
      tokenIn
      tokenOut
      blockTimestamp
      transactionHash
    }
  }
`

export interface DepositRecord {
  id: string
  amount: string
  token: string
  blockTimestamp: string
  transactionHash: string
}

export interface BorrowRecord extends DepositRecord {}
export interface RepayRecord extends DepositRecord {}
export interface SwapRecord {
  id: string
  amountIn: string
  amountOut: string
  tokenIn: string
  tokenOut: string
  blockTimestamp: string
  transactionHash: string
}

export interface UserHistory {
  deposits: DepositRecord[]
  borrows: BorrowRecord[]
  repays: RepayRecord[]
  swaps: SwapRecord[]
}

export async function fetchUserDeposits(userAddress: string): Promise<UserHistory> {
  try {
    const data = await request<UserHistory>(
      SUBGRAPH_URL,
      GET_USER_DEPOSITS,
      { user: userAddress.toLowerCase() }
    )
    return {
      deposits: data?.deposits || [],
      borrows:  data?.borrows  || [],
      repays:   data?.repays   || [],
      swaps:    data?.swaps    || [],
    }
  } catch (error) {
    console.error('Ошибка при десериализации логов сабграфа:', error)
    return { deposits: [], borrows: [], repays: [], swaps: [] }
  }
}