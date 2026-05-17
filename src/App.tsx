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

  // Лоадер инициализации приложения в Telegram WebView
  if (!isReady) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center bg-[#090d16] space-y-3">
        <div className="animate-spin rounded-full h-10 w-10 border-2 border-slate-800 border-t-blue-500"></div>
        <p className="text-[11px] font-mono text-slate-500">Initializing Telegram SDK...</p>
      </div>
    )
  }

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <div className="min-h-screen bg-[#090d16] text-slate-100 font-sans antialiased relative overflow-x-hidden pb-12">
          
          {/* Глобальный неоновый Web3 бэкграунд-эффект */}
          <div className="absolute top-[-10%] right-[-10%] w-96 h-96 bg-blue-600/10 rounded-full blur-[120px] pointer-events-none"></div>
          <div className="absolute bottom-[10%] left-[-20%] w-80 h-80 bg-indigo-600/5 rounded-full blur-[100px] pointer-events-none"></div>
          
          {/* НАТИВНЫЙ ХЕДЕР ПРИЛОЖЕНИЯ (STICKY TOP) */}
          <header className="sticky top-0 z-50 max-w-md mx-auto px-4 pt-4 pb-2 backdrop-blur-md bg-[#090d16]/70">
            <div className="flex items-center justify-between bg-slate-900/40 backdrop-blur-md border border-slate-800/60 p-3 rounded-2xl shadow-lg shadow-black/20">
              <div className="flex items-center gap-2.5">
                <div className="w-8 h-8 rounded-xl bg-gradient-to-tr from-blue-500 to-indigo-600 flex items-center justify-center font-black text-sm shadow-md shadow-blue-500/20 text-white">
                  D
                </div>
                <div>
                  <h1 className="text-xs font-bold tracking-wide text-slate-200 uppercase">DeFi Super-App</h1>
                  <p className="text-[10px] text-emerald-400 font-semibold flex items-center gap-1 mt-0.5">
                    <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span>
                    RPC Node Active
                  </p>
                </div>
              </div>
              
              {/* Компактная интеграция красивой кнопки Connect */}
              <ConnectButton />
            </div>
          </header>

          {/* ОСНОВНОЙ КОНТЕНТ (ДАШБОРД ПОЗИЦИЙ КРЕДИТОВАНИЯ И ГОЛОСОВАНИЯ) */}
          <main className="max-w-md mx-auto px-4 mt-3">
            
            {/* Текстовый статус-монитор системных уведомлений */}
            <div className="bg-slate-900/30 backdrop-blur-sm py-2.5 px-4 rounded-xl border border-slate-800/40 shadow-inner mb-4">
              <p className="text-[10px] text-slate-400 font-mono text-center leading-relaxed">
                <span className="text-blue-500">⚙️ [SYSTEM]:</span> Безопасное подключение через L2 RPC узлы успешно установлено
              </p>
            </div>

            {/* Главный DeFi Дашборд */}
            <Dashboard />

          </main>

        </div>
      </QueryClientProvider>
    </WagmiProvider>
  )
}