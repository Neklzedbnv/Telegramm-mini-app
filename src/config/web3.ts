import { http, createConfig } from 'wagmi'
import { arbitrumSepolia, optimismSepolia } from 'wagmi/chains'
import { createWeb3Modal } from '@web3modal/wagmi/react'

// Твой персональный ключ от WalletConnect Cloud
export const projectId = 'YOUR_WALLETCONNECT_PROJECT_ID' 

if (!projectId || projectId === 'YOUR_WALLETCONNECT_PROJECT_ID') {
  throw new Error('Критическая ошибка фронтенда: Не инициализирован WalletConnect Project ID.')
}

// Профессор требует поддержку L2 Rollups
export const chains = [arbitrumSepolia, optimismSepolia] as const

export const wagmiConfig = createConfig({
  chains,
  transports: {
    [arbitrumSepolia.id]: http(),
    [optimismSepolia.id]: http(),
  },
})

// Кастомизируем внешний вид окна подключения под дизайн Telegram
createWeb3Modal({
  wagmiConfig,
  projectId,
  enableAnalytics: false,
  themeMode: 'dark',
  themeVariables: {
    '--w3m-accent': '#2563eb', // Фирменный нативный синий цвет Telegram
    '--w3m-border-radius-master': '16px',
    '--w3m-font-family': 'sans-serif',
    '--w3m-z-index': 9999
  }
})