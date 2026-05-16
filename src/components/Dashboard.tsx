import { useState, useEffect } from 'react'
import { mainButton } from '@telegram-apps/sdk-react'
import { useNetworkCheck } from '../hooks/useNetworkCheck'

export function Dashboard() {
  const { isConnected, isWrongNetwork } = useNetworkCheck()
  
  const [supplied] = useState("1.50") 
  const [borrowed] = useState("1200.00") 
  const [healthFactor] = useState(1.75) 
  
  const [proposals] = useState([
    { id: 1, title: "PIP-01: Повысить LTV для коллатерала ETH до 80%", state: "Active" },
    { id: 2, title: "PIP-02: Интеграция Chainlink оракула для Arbitrum Sepolia", state: "Executed" }
  ])

  useEffect(() => {
    if (isConnected && !isWrongNetwork) {
      if (mainButton.mount.isAvailable()) {
        mainButton.mount()
        
        // Используем метод setParams, который железно поддерживается типами SDK
        mainButton.setParams({
          text: 'ДЕПОЗИТ В VAULT (ERC-4626)',
          backgroundColor: '#2563eb', 
          textColor: '#ffffff',
          isVisible: true,
          isEnabled: true
        })

        const handleMainButtonClick = () => {
          alert('Инициализация транзакции через смарт-контракт Vault...')
        }

        const unsubscribe = mainButton.onClick(handleMainButtonClick)
        
        return () => {
          unsubscribe()
          // Скрываем кнопку при размонтировании
          mainButton.setParams({ isVisible: false })
        }
      }
    } else {
      if (mainButton.isMounted()) {
        mainButton.setParams({ isVisible: false })
      }
    }
  }, [isConnected, isWrongNetwork])

  const getHealthFactorColor = (hf: number) => {
    if (hf > 2.0) return 'text-emerald-400 border-emerald-500/30 bg-emerald-500/10'
    if (hf > 1.2) return 'text-amber-400 border-amber-500/30 bg-amber-500/10'
    return 'text-red-400 border-red-500/30 bg-red-500/10'
  }

  if (!isConnected || isWrongNetwork) {
    return (
      <div className="mt-6 p-6 bg-tgSecondaryBg/60 rounded-3xl border border-slate-800/40 text-center space-y-2">
        <p className="text-sm text-tgHint font-medium font-sans">
          Подключите валидный L2 кошелек для доступа к DeFi позициям и голосованию DAO.
        </p>
      </div>
    )
  }

  return (
    <div className="mt-6 space-y-5 pb-24">
      {/* Метрика Health Factor */}
      <div className={`p-4 rounded-2xl border flex items-center justify-between ${getHealthFactorColor(healthFactor)}`}>
        <div>
          <h4 className="text-xs uppercase font-mono tracking-wider opacity-80">Health Factor</h4>
          <p className="text-2xl font-black tracking-tight mt-0.5">{healthFactor.toFixed(2)}</p>
        </div>
        <div className="text-right text-xs font-mono max-w-[180px] opacity-90">
          {healthFactor > 1.0 ? '✓ Позиция безопасна' : '⚠️ Риск ликвидации!'}
        </div>
      </div>

      {/* Основные DeFi показатели */}
      <div className="grid grid-cols-2 gap-3">
        <div className="bg-tgSecondaryBg p-4 rounded-2xl border border-slate-800/50">
          <span className="text-[10px] uppercase font-mono text-tgHint tracking-wider">Total Supplied</span>
          <p className="text-lg font-bold text-tgText mt-1">{supplied} <span className="text-xs text-tgLink font-sans">ETH</span></p>
        </div>

        <div className="bg-tgSecondaryBg p-4 rounded-2xl border border-slate-800/50">
          <span className="text-[10px] uppercase font-mono text-tgHint tracking-wider">Total Borrowed</span>
          <p className="text-lg font-bold text-tgText mt-1">${borrowed} <span className="text-xs text-slate-500 font-sans">USDC</span></p>
        </div>
      </div>

      {/* Секция управления DAO (Требование Силлабуса) */}
      <div className="bg-tgSecondaryBg/80 p-4 rounded-2xl border border-slate-800/40 space-y-3">
        <h3 className="text-xs font-bold text-tgHint uppercase tracking-wider font-mono">Активные голосования Governance</h3>
        <div className="space-y-2">
          {proposals.map((prop) => (
            <div key={prop.id} className="p-3 bg-slate-900/60 rounded-xl border border-slate-800/30 flex items-center justify-between">
              <div className="max-w-[70%]">
                <p className="text-xs font-medium text-tgText truncate">{prop.title}</p>
              </div>
              <span className={`text-[10px] px-2 py-0.5 font-mono font-bold rounded-md ${
                prop.state === 'Active' ? 'bg-blue-500/20 text-blue-400 border border-blue-500/30' : 'bg-slate-800 text-tgHint'
              }`}>
                {prop.state}
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}