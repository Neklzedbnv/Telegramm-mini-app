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
  
  // Явное приведение типов (Type Assertion) для обхода ошибки TS7053
  const contractFields = accountData as readonly [bigint, bigint, bigint, bigint, bigint, bigint] | undefined

  const supplied = contractFields ? parseFloat(formatUnits(contractFields[0], 18)).toFixed(2) : "0.00"
  const borrowed = contractFields ? parseFloat(formatUnits(contractFields[1], 18)).toFixed(2) : "0.00"
  const healthFactor = contractFields ? parseFloat(formatUnits(contractFields[5], 18)) : 0.00

  const [proposals] = useState([
    { id: 1, title: "PIP-01: Повысить LTV для коллатерала ETH до 80%", state: "Active" },
    { id: 2, title: "PIP-02: Интеграция Chainlink оракула для Arbitrum Sepolia", state: "Executed" }
  ])

  // ТРАНЗАКЦИЯ 1: Функция для отправки депозита (привязана к Telegram MainButton)
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

  // ТРАНЗАКЦИЯ 2: Функция займа (Borrow) под залог заведенных активов
  const handleBorrow = () => {
    const mockAmount = parseUnits("50", 6) // Условные 50 USDC (6 знаков)
    const mockAsset = "0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e" 

    writeContract({
      address: CONTRACT_ADDRESSES.LENDING_POOL,
      abi: LENDING_POOL_ABI,
      functionName: 'borrow',
      args: [mockAsset, mockAmount],
    })
  }

  // ТРАНЗАКЦИЯ 3: Функция голосования в OpenZeppelin Governor
  const handleVote = (proposalId: number, support: number) => {
    writeContract({
      address: CONTRACT_ADDRESSES.GOVERNOR, 
      abi: [
        {
          inputs: [
            { name: 'proposalId', type: 'uint256' },
            { name: 'support', type: 'uint8' }
          ],
          name: 'castVote',
          outputs: [{ name: 'weight', type: 'uint256' }],
          stateMutability: 'external',
          type: 'function'
        }
      ] as const, // Обеспечивает строгое соответствие сигнатуры типов
      functionName: 'castVote',
      args: [BigInt(proposalId), support],
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
        <div className="bg-tgSecondaryBg p-4 rounded-2xl border border-slate-800/50 flex flex-col justify-between">
          <div>
            <span className="text-[10px] uppercase font-mono text-tgHint tracking-wider">Total Supplied</span>
            <p className="text-lg font-bold text-tgText mt-1">{supplied} <span className="text-xs text-tgLink font-sans">ETH</span></p>
          </div>
        </div>

        <div className="bg-tgSecondaryBg p-4 rounded-2xl border border-slate-800/50 space-y-3">
          <div>
            <span className="text-[10px] uppercase font-mono text-tgHint tracking-wider">Total Borrowed</span>
            <p className="text-lg font-bold text-tgText mt-1">${borrowed} <span className="text-xs text-slate-500 font-sans">USDC</span></p>
          </div>
          <button 
            onClick={handleBorrow}
            disabled={isPending || isMining}
            className="w-full py-1.5 bg-tgLink text-white rounded-xl text-xs font-bold font-sans hover:opacity-90 disabled:opacity-40 transition-all"
          >
            Borrow 50 USDC
          </button>
        </div>
      </div>

      {/* Секция управления DAO */}
      <div className="bg-tgSecondaryBg/80 p-4 rounded-2xl border border-slate-800/40 space-y-3">
        <h3 className="text-xs font-bold text-tgHint uppercase tracking-wider font-mono">Активные голосования Governance</h3>
        <div className="space-y-2">
          {proposals.map((prop) => (
            <div key={prop.id} className="p-3 bg-slate-900/60 rounded-xl border border-slate-800/30 flex flex-col space-y-3">
              <div className="flex items-center justify-between">
                <div className="max-w-[70%]">
                  <p className="text-xs font-medium text-tgText truncate">{prop.title}</p>
                </div>
                <span className={`text-[10px] px-2 py-0.5 font-mono font-bold rounded-md ${
                  prop.state === 'Active' ? 'bg-blue-500/20 text-blue-400 border border-blue-500/30' : 'bg-slate-800 text-tgHint'
                }`}>
                  {prop.state}
                </span>
              </div>

              {/* Блок интерактивного голосования для активных пропозалов */}
              {prop.state === 'Active' && (
                <div className="grid grid-cols-3 gap-2 pt-1">
                  <button
                    onClick={() => handleVote(prop.id, 1)}
                    disabled={isPending || isMining}
                    className="py-1.5 bg-emerald-500/10 hover:bg-emerald-500/20 text-emerald-400 rounded-lg text-[10px] font-mono font-bold border border-emerald-500/20 transition-all disabled:opacity-40"
                  >
                    За
                  </button>
                  <button
                    onClick={() => handleVote(prop.id, 0)}
                    disabled={isPending || isMining}
                    className="py-1.5 bg-red-500/10 hover:bg-red-500/20 text-red-400 rounded-lg text-[10px] font-mono font-bold border border-red-500/20 transition-all disabled:opacity-40"
                  >
                    Против
                  </button>
                  <button
                    onClick={() => handleVote(prop.id, 2)}
                    disabled={isPending || isMining}
                    className="py-1.5 bg-slate-800 hover:bg-slate-700 text-tgHint rounded-lg text-[10px] font-mono font-bold border border-slate-700 transition-all disabled:opacity-40"
                  >
                    Воздерж.
                  </button>
                </div>
              )}
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