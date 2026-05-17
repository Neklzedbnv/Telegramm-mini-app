import { http, createConfig } from 'wagmi'
import { arbitrumSepolia, optimismSepolia } from 'wagmi/chains'
import { createWeb3Modal } from '@web3modal/wagmi/react'

// Считываем ключ из переменных окружения Vite
const envProjectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID 

/**
 * Защитный блок: если в .env файле пусто или остался дефолтный шаблон,
 * подставляем публичный девелоперский ID, чтобы локальный рендеринг и тесты не падали.
 */
const projectId = (!envProjectId || envProjectId === 'YOUR_WALLETCONNECT_PROJECT_ID')
  ? '95a3815f91fec4678855db88588527a2' // Публичный тестовый Project ID
  : envProjectId

// Arbitrum Sepolia с повышенным множителем комиссий (избегает "max fee < base fee")
const arbitrumSepoliaWithFees = {
  ...arbitrumSepolia,
  fees: {
    baseFeeMultiplier: 1.5,
  },
} as const

// Официальное требование силлабуса: поддержка Layer 2 Rollups решений
export const chains = [arbitrumSepoliaWithFees, optimismSepolia] as const

export const wagmiConfig = createConfig({
  chains,
  transports: {
    [arbitrumSepoliaWithFees.id]: http('https://sepolia-rollup.arbitrum.io/rpc', {
      fetchOptions: { cache: 'no-store' },
    }),
    [optimismSepolia.id]: http(),
  },
})

// Настройка модального окна WalletConnect под нативный интерфейс мессенджера Telegram
createWeb3Modal({
  wagmiConfig,
  projectId,
  enableAnalytics: false,
  themeMode: 'dark',
  themeVariables: {
    '--w3m-accent': '#2563eb',          // Фирменный синий цвет Telegram (кнопки, активные элементы)
    '--w3m-border-radius-master': '16px', // Закругленные углы в стиле Telegram UI
    '--w3m-font-family': 'sans-serif',
    '--w3m-z-index': 9999
  }
})