import { request, gql } from 'graphql-request'

// Тестовый Endpoint сабграфа (замени на актуальный URL твоего сабграфа в The Graph)
const SUBGRAPH_URL = 'https://api.studio.thegraph.com/query/1753457/lending-pool-subgraph/v0.0.1'

// GraphQL Query для получения последних 5 депозитов пользователя
export const GET_USER_DEPOSITS = gql`
  query GetUserDeposits($user: String!) {
    deposits(first: 5, orderBy: timestamp, orderDirection: desc, where: { user: $user }) {
      id
      amount
      timestamp
      asset
    }
  }
`

export interface DepositRecord {
  id: string
  amount: string
  timestamp: string
  asset: string
}

export async function fetchUserDeposits(userAddress: string): Promise<DepositRecord[]> {
  try {
    // Безопасно типизируем ответ, допуская, что deposits может отсутствовать в объекте данных
    const data = await request<{ deposits?: DepositRecord[] }>(
      SUBGRAPH_URL, 
      GET_USER_DEPOSITS, 
      { user: userAddress.toLowerCase() }
    )
    
    // Защита: если data или data.deposits равен undefined/null, возвращаем чистый пустой массив
    return data?.deposits || []
    
  } catch (error) {
    console.error('Ошибка при десериализации логов сабграфа:', error)
    return []
  }
}