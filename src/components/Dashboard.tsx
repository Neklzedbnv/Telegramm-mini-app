import { useState, useEffect } from 'react'
import { mainButton } from '@telegram-apps/sdk-react'
import { useNetworkCheck } from '../hooks/useNetworkCheck'
import { useReadContract, useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACT_ADDRESSES, LENDING_POOL_ABI } from '../config/contracts'
import { formatUnits, parseUnits } from 'viem'
import { useQuery } from '@tanstack/react-query'
import { fetchUserDeposits } from '../config/graphql'

export function Dashboard() {
  const { isConnected, isWrongNetwork } = useNetworkCheck()
  const { address } = useAccount()
  
  // Хуки для отправки транзакции
  const { writeContract, data: hash, error: writeError, isPending } = useWriteContract()
  
  // Отслеживание статуса транзакции в блокчейне (майнинг)
  const { isLoading: isMining, isSuccess: isTxSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  // Читаем реальные данные с контракта
  const { data: accountData, isLoading: isContractLoading } = useReadContract({
    address: CONTRACT_ADDRESSES.LENDING_POOL,
    abi: LENDING_POOL_ABI,
    functionName: 'getUserAccountData',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address && !isWrongNetwork,
    }
  })

  // Хук React Query для получения истории транзакций из The Graph Subgraph
  const { data: depositHistory } = useQuery({
    queryKey: ['userDeposits', address],
    queryFn: () => fetchUserDeposits(address!),
    enabled: !!address && !isWrongNetwork,
    refetchInterval: 10000, // Автообновление логов каждые 10 секунд
  })
  
  const supplied = accountData ? parseFloat(formatUnits(accountData[0], 18)).toFixed(2) : "0.00"
  const borrowed = accountData ? parseFloat(formatUnits(accountData[1], 18)).toFixed(2) : "0.00"
  const healthFactor = accountData ? parseFloat(formatUnits(accountData[5], 18)) : 0.00

  const [proposals] = useState([
    { id: 1, title: "PIP-01: Повысить LTV для коллатерала ETH до 80%", state: "Active" },
    { id: 2, title: "PIP-02: Интеграция Chainlink оракула для Arbitrum Sepolia", state: "Executed" }
  ])

  // Функция для отправки депозита
  const handleDeposit = () => {
    const mockAmount = parseUnits("0.1", 18)
    const mockAsset = "0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889" 

    writeContract({
      address: CONTRACT_ADDRESSES.LENDING_POOL,
      abi: LENDING_POOL_ABI,
      functionName: 'deposit',
      args: [mockAsset, mockAmount],
    })
  }

  // Синхронизация нативной кнопки Telegram с жизненным циклом транзакции
  useEffect(() => {
    if (isConnected && !isWrongNetwork) {
      if (mainButton.mount.isAvailable()) {
        mainButton.mount()
        
        mainButton.setParams({
          text: isPending ? 'ПОДТВЕРДИТЕ В КОШЕЛЬКЕ...' : isMining ? 'ОБРАБОТКА ТРАНЗАКЦИИ...' : 'ДЕПОЗИТ 0.1 ETH В VAULT',
          backgroundColor: isPending || isMining ? '#94a3b8' : '#2563eb', 
          textColor: '#ffffff',
          isVisible: true,
          isEnabled: !isPending && !isMining
        })

        const unsubscribe = mainButton.onClick(handleDeposit)
        
        return () => {
          unsubscribe()
          mainButton.setParams({ isVisible: false })
        }
      }
    } else {
      if (mainButton.isMounted()) {
        mainButton.setParams({ isVisible: false })
      }
    }
  }, [isConnected, isWrongNetwork, isPending, isMining])

  const getHealthFactorColor = (hf: number) => {
    if (hf === 0) return 'text-slate-400 border-slate-800 bg-slate-900/40'
    if (hf > 2.0) return 'text-emerald-400 border-emerald-500/30 bg-emerald-500/10'
    if (hf > 1.1) return 'text-amber-400 border-amber-500/30 bg-amber-500/10'
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

  if (isContractLoading) {
    return (
      <div className="mt-6 p-8 text-center">
        <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-b-2 border-tgLink mx-auto"></div>
        <p className="text-xs text-tgHint mt-3 font-mono">Запрос состояния Ledger...</p>
      </div>
    )
  }

  return (
    <div className="mt-6 space-y-5 pb-24">
      {/* Информационные плашки статуса транзакции */}
      {hash && (
        <div className="p-3 bg-slate-900 rounded-xl border border-slate-800 text-xs font-mono space-y-1">
          <p className="text-tgHint">Tx Hash: <span className="text-tgText break-all text-[11px]">{hash}</span></p>
          {isMining && <p className="text-amber-400 animate-pulse">● Майнинг транзакции в L2 сети...</p>}
          {isTxSuccess && <p className="text-emerald-400">✓ Транзакция успешно подтверждена!</p>}
          {writeError && (
            <p className="text-red-400">
              ⚠️ Ошибка: {(writeError as any).shortMessage || (writeError as any).message || 'Отклонено пользователем'}
            </p>
          )}
        </div>
      )}

      {/* Метрика Health Factor */}
      <div className={`p-4 rounded-2xl border flex items-center justify-between ${getHealthFactorColor(healthFactor)}`}>
        <div>
          <h4 className="text-xs uppercase font-mono tracking-wider opacity-80">Health Factor</h4>
          <p className="text-2xl font-black tracking-tight mt-0.5">
            {healthFactor === 0 ? '—' : healthFactor > 100 ? '∞' : healthFactor.toFixed(2)}
          </p>
        </div>
        <div className="text-right text-xs font-mono max-w-[180px] opacity-90">
          {healthFactor === 0 ? 'Нет активных займов' : healthFactor > 1.1 ? '✓ Позиция безопасна' : '⚠️ Риск ликвидации!'}
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

      {/* Секция управления DAO */}
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

      {/* Секция истории транзакций из The Graph */}
      <div className="bg-tgSecondaryBg/80 p-4 rounded-2xl border border-slate-800/40 space-y-3">
        <h3 className="text-xs font-bold text-tgHint uppercase tracking-wider font-mono">История операций (The Graph Subgraph)</h3>
        <div className="space-y-2">
          {depositHistory && depositHistory.length > 0 ? (
            depositHistory.map((tx) => (
              <div key={tx.id} className="p-3 bg-slate-900/40 rounded-xl border border-slate-800/20 flex items-center justify-between text-xs font-mono">
                <div>
                  <p className="text-emerald-400 font-bold">↓ Deposit</p>
                  <p className="text-[10px] text-tgHint mt-0.5">
                    {new Date(parseInt(tx.timestamp) * 1000).toLocaleTimeString()}
                  </p>
                </div>
                <p className="text-tgText font-bold">
                  {parseFloat(formatUnits(BigInt(tx.amount), 18)).toFixed(2)} <span className="text-[10px] text-tgLink">ETH</span>
                </p>
              </div>
            ))
          ) : (
            <p className="text-xs text-tgHint py-2 text-center font-sans">История депозитов пуста или сабграф синхронизируется.</p>
          )}
        </div>
      </div>
    </div>
  )
}