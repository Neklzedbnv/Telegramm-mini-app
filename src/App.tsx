import { useEffect, useState } from 'react'
import { init, miniApp, themeParams } from '@telegram-apps/sdk-react'
import { WagmiProvider } from 'wagmi'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { wagmiConfig } from './config/web3'
import { ConnectButton } from './components/ConnectButton'
import { Dashboard } from './components/Dashboard'

// Оптимальный клиент для кэширования блокчейн-данных
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: false, // Защита от дублирующих RPC-запросов при переключениях окон внутри ТГ
      retry: 1,
    },
  },
})

export default function App() {
  const [isReady, setIsReady] = useState(false)

  useEffect(() => {
    try {
      // Инициализируем нативные методы Telegram Mini Apps
      init()
      
      if (miniApp.mount.isAvailable()) {
        miniApp.mount()
        miniApp.setHeaderColor('bg_color')
      }
      
      if (themeParams.mount.isAvailable()) {
        themeParams.mount()
      }

      setIsReady(true)
    } catch (error) {
      console.warn("Development mode: Запущено в обычном браузере. Включен Web-fallback режим.")
      setIsReady(true) 
    }
  }, [])

  if (!isReady) {
    return (
      <div className="flex h-screen items-center justify-center bg-slate-950">
        <div className="animate-spin rounded-full h-10 w-10 border-t-2 border-b-2 border-blue-500"></div>
      </div>
    )
  }

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <main className="min-h-screen bg-tgBg text-tgText p-4 max-w-md mx-auto transition-colors duration-200">
          
          {/* Хедер приложения */}
          <div className="text-center mt-8 space-y-3">
            <h1 className="text-2xl font-black text-tgLink tracking-wide uppercase">DeFi Super-App</h1>
            <div className="bg-tgSecondaryBg py-3 px-4 rounded-2xl border border-slate-800/40 shadow-xl">
              <p className="text-xs text-tgHint font-mono leading-relaxed">
                [SYSTEM]: Безопасное подключение через L2 RPC узлы настроено.
              </p>
            </div>
          </div>

          {/* Секция авторизации Web3 кошелька */}
          <div className="mt-6 bg-slate-900/40 p-4 rounded-2xl border border-slate-800/30">
            <h2 className="text-xs font-bold text-tgHint uppercase tracking-wider mb-3 font-mono">Web3 Account</h2>
            <ConnectButton />
          </div>

          {/* Главный DeFi Дашборд позиций кредитования */}
          <Dashboard />

        </main>
      </QueryClientProvider>
    </WagmiProvider>
  )
}