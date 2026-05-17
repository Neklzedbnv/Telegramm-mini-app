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
      ] as const, 
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
          backgroundColor: isPending || isMining ? '#475569' : '#2563eb', 
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

  const getHealthFactorStyles = (hf: number) => {
    if (hf === 0) return 'text-slate-400 border-slate-800/80 bg-slate-900/40 backdrop-blur-md'
    if (hf > 2.0) return 'text-emerald-400 border-emerald-500/20 bg-emerald-500/5 backdrop-blur-md shadow-lg shadow-emerald-500/5'
    if (hf > 1.1) return 'text-amber-400 border-amber-500/20 bg-amber-500/5 backdrop-blur-md shadow-lg shadow-amber-500/5'
    return 'text-red-400 border-red-500/20 bg-red-500/5 backdrop-blur-md shadow-lg shadow-red-500/5 animate-pulse'
  }

  if (!isConnected || isWrongNetwork) {
    return (
      <div className="relative min-h-[80vh] flex items-center justify-center p-4">
        <div className="absolute top-[20%] left-[-10%] w-64 h-64 bg-blue-600/10 rounded-full blur-3xl pointer-events-none"></div>
        <div className="w-full max-w-sm p-6 bg-slate-900/60 backdrop-blur-xl rounded-3xl border border-slate-800/60 text-center space-y-4 shadow-xl">
          <div className="w-12 h-12 rounded-full bg-blue-500/10 border border-blue-500/20 flex items-center justify-center mx-auto text-blue-400 text-lg">
            ⚡
          </div>
          <div className="space-y-1.5">
            <h3 className="text-sm font-bold text-slate-200">Требуется авторизация</h3>
            <p className="text-xs text-slate-400 leading-relaxed px-4">
              Подключите валидный Layer 2 кошелек через верхнюю панель для доступа к DeFi позициям и голосованию DAO.
            </p>
          </div>
        </div>
      </div>
    )
  }

  if (isContractLoading) {
    return (
      <div className="min-h-[70vh] flex flex-col items-center justify-center space-y-4">
        <div className="relative w-10 h-10">
          <div className="animate-spin rounded-full h-10 w-10 border-2 border-slate-800 border-t-blue-500"></div>
          <div className="absolute inset-0 m-auto w-2 h-2 bg-blue-400 rounded-full animate-ping"></div>
        </div>
        <div className="text-center">
          <p className="text-xs font-semibold text-slate-300">Запрос состояния Ledger</p>
          <p className="text-[10px] text-slate-500 font-mono mt-0.5">Синхронизация RPC нод...</p>
        </div>
      </div>
    )
  }

  return (
    <div className="relative space-y-5 pb-24 px-1 select-none">
      
      {/* Мягкие неоновые Web3 эффекты глубины на бэкграунде */}
      <div className="absolute top-[-10%] left-[-20%] w-64 h-64 bg-blue-600/10 rounded-full blur-3xl pointer-events-none"></div>
      <div className="absolute top-[30%] right-[-20%] w-72 h-72 bg-emerald-600/5 rounded-full blur-3xl pointer-events-none"></div>

      {/* Информационные плашки статуса транзакции (всплывают при наличии хеша) */}
      {hash && (
        <div className="p-3.5 bg-slate-900/80 backdrop-blur-md rounded-2xl border border-slate-800/80 text-xs font-mono space-y-2 shadow-lg transition-all">
          <div className="flex items-center justify-between border-b border-slate-800/60 pb-1.5">
            <span className="text-slate-500">Status Monitor</span>
            <a 
              href={`https://sepolia.arbiscan.io/tx/${hash}`} 
              target="_blank" 
              rel="noreferrer" 
              className="text-blue-400 hover:underline text-[10px]"
            >
              Explorer ↗
            </a>
          </div>
          <p className="text-slate-400 flex items-center gap-1.5 truncate">
            <span className="text-slate-600">Hash:</span> 
            <span className="text-slate-300 text-[11px]">{hash}</span>
          </p>
          {isMining && (
            <p className="text-amber-400 flex items-center gap-1.5 font-medium">
              <span className="w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse"></span>
              Майнинг транзакции в L2 сети...
            </p>
          )}
          {isTxSuccess && (
            <p className="text-emerald-400 flex items-center gap-1.5 font-medium">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400"></span>
              ✓ Транзакция успешно подтверждена!
            </p>
          )}
          {writeError && (
            <p className="text-rose-400 flex items-start gap-1.5 leading-relaxed">
              <span>⚠️</span>
              <span>Ошибка: {(writeError as any).shortMessage || (writeError as any).message || 'Отклонено пользователем'}</span>
            </p>
          )}
        </div>
      )}

      {/* Метрика Health Factor */}
      <div className={`p-4 rounded-2xl border flex items-center justify-between transition-all ${getHealthFactorStyles(healthFactor)}`}>
        <div className="space-y-0.5">
          <h4 className="text-[10px] uppercase font-bold tracking-wider text-slate-400">Health Factor</h4>
          <p className="text-2xl font-black tracking-tight">
            {healthFactor === 0 ? '—' : healthFactor > 100 ? '∞' : healthFactor.toFixed(2)}
          </p>
        </div>
        <div className="text-right">
          {healthFactor === 0 ? (
            <span className="text-[10px] px-2 py-0.5 rounded-md bg-slate-800 text-slate-400 font-medium border border-slate-700/50">
              No Active Loans
            </span>
          ) : healthFactor > 1.1 ? (
            <span className="text-[10px] px-2 py-0.5 rounded-md bg-emerald-500/10 text-emerald-400 font-bold border border-emerald-500/20">
              ✓ Safe Position
            </span>
          ) : (
            <span className="text-[10px] px-2 py-0.5 rounded-md bg-rose-500/10 text-rose-400 font-bold border border-rose-500/20 animate-bounce">
              ⚠️ High Risk
            </span>
          )}
          <p className="text-[10px] text-slate-500 mt-1 font-medium">Liquidation threshold &lt; 1.0</p>
        </div>
      </div>

      {/* Основные DeFi показатели (Total Supplied & Total Borrowed) */}
      <div className="grid grid-cols-2 gap-3">
        
        {/* Карточка Supply */}
        <div className="bg-slate-900/50 backdrop-blur-md p-4 rounded-2xl border border-slate-800/60 flex flex-col justify-between min-h-[95px] relative overflow-hidden group shadow-md">
          <div className="space-y-1">
            <span className="text-[10px] uppercase font-bold text-slate-400 tracking-wider">Total Supplied</span>
            <p className="text-xl font-black text-white tracking-tight">
              {supplied} <span className="text-xs text-blue-400 font-medium font-sans">ETH</span>
            </p>
          </div>
          <div className="absolute bottom-0 left-0 w-full h-[1.5px] bg-gradient-to-r from-blue-500 to-indigo-500 scale-x-0 group-hover:scale-x-100 transition-transform duration-300"></div>
        </div>

        {/* Карточка Borrow */}
        <div className="bg-slate-900/50 backdrop-blur-md p-4 rounded-2xl border border-slate-800/60 flex flex-col justify-between min-h-[125px] relative overflow-hidden group shadow-md">
          <div className="space-y-1">
            <span className="text-[10px] uppercase font-bold text-slate-400 tracking-wider">Total Borrowed</span>
            <p className="text-xl font-black text-white tracking-tight">
              ${borrowed} <span className="text-xs text-purple-400 font-medium font-sans">USDC</span>
            </p>
          </div>
          
          <button 
            onClick={handleBorrow}
            disabled={isPending || isMining}
            className="w-full py-2 bg-gradient-to-r from-purple-600 to-indigo-600 hover:from-purple-500 hover:to-indigo-500 active:scale-[0.97] text-white rounded-xl text-xs font-bold shadow-md shadow-purple-950/40 disabled:opacity-30 disabled:pointer-events-none transition-all mt-2"
          >
            Borrow 50 USDC
          </button>
          <div className="absolute bottom-0 left-0 w-full h-[1.5px] bg-gradient-to-r from-purple-500 to-pink-500 scale-x-0 group-hover:scale-x-100 transition-transform duration-300"></div>
        </div>

      </div>

      {/* Секция управления DAO (Governance UI) */}
      <div className="bg-slate-900/40 backdrop-blur-md p-4 rounded-2xl border border-slate-800/60 space-y-3.5 shadow-md">
        <div className="flex items-center justify-between">
          <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider">DAO Governance</h3>
          <span className="text-[9px] px-2 py-0.5 rounded-full bg-blue-500/10 text-blue-400 border border-blue-500/20 font-bold">
            OpenZeppelin Governor
          </span>
        </div>
        
        <div className="space-y-2.5">
          {proposals.map((prop) => (
            <div key={prop.id} className="p-3 bg-slate-950/40 rounded-xl border border-slate-900 flex flex-col space-y-3">
              <div className="flex items-start justify-between gap-3">
                <p className="text-xs font-semibold text-slate-200 leading-relaxed">{prop.title}</p>
                <span className={`text-[9px] px-2 py-0.5 font-bold rounded-md shrink-0 ${
                  prop.state === 'Active' 
                    ? 'bg-blue-500/10 text-blue-400 border border-blue-500/20 shadow-sm shadow-blue-500/5' 
                    : 'bg-slate-800 text-slate-400'
                }`}>
                  {prop.state}
                </span>
              </div>

              {/* Блок интерактивного голосования для активных пропозалов */}
              {prop.state === 'Active' && (
                <div className="grid grid-cols-3 gap-2 pt-0.5">
                  <button
                    onClick={() => handleVote(prop.id, 1)}
                    disabled={isPending || isMining}
                    className="py-1.5 bg-emerald-500/5 hover:bg-emerald-500/10 active:scale-[0.96] text-emerald-400 rounded-lg text-[11px] font-bold border border-emerald-500/10 transition-all disabled:opacity-30"
                  >
                    За
                  </button>
                  <button
                    onClick={() => handleVote(prop.id, 0)}
                    disabled={isPending || isMining}
                    className="py-1.5 bg-rose-500/5 hover:bg-rose-500/10 active:scale-[0.96] text-rose-400 rounded-lg text-[11px] font-bold border border-rose-500/10 transition-all disabled:opacity-30"
                  >
                    Против
                  </button>
                  <button
                    onClick={() => handleVote(prop.id, 2)}
                    disabled={isPending || isMining}
                    className="py-1.5 bg-slate-800/40 hover:bg-slate-800/80 active:scale-[0.96] text-slate-400 rounded-lg text-[11px] font-bold border border-slate-700/40 transition-all disabled:opacity-30"
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
      <div className="bg-slate-900/40 backdrop-blur-md p-4 rounded-2xl border border-slate-800/60 space-y-3.5 shadow-md">
        <div className="flex items-center justify-between">
          <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider">История операций</h3>
          <span className="text-[9px] px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-bold">
            The Graph Subgraph
          </span>
        </div>

        <div className="space-y-2 max-h-[180px] overflow-y-auto pr-0.5">
          {depositHistory && depositHistory.length > 0 ? (
            depositHistory.map((tx) => (
              <div key={tx.id} className="p-3 bg-slate-950/40 rounded-xl border border-slate-900/60 flex items-center justify-between text-xs transition-colors hover:bg-slate-950/80">
                <div className="space-y-0.5">
                  <p className="text-emerald-400 font-bold flex items-center gap-1">
                    <span className="text-[10px]">↓</span> Deposit Assets
                  </p>
                  <p className="text-[10px] text-slate-500 font-mono">
                    {new Date(parseInt(tx.timestamp) * 1000).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}
                  </p>
                </div>
                <p className="text-slate-100 font-black tracking-tight text-right">
                  {parseFloat(formatUnits(BigInt(tx.amount), 18)).toFixed(2)} <span className="text-[10px] text-blue-400 font-medium">ETH</span>
                </p>
              </div>
            ))
          ) : (
            <div className="py-6 text-center space-y-1 border border-dashed border-slate-800/60 rounded-xl bg-slate-950/10">
              <p className="text-xs text-slate-400 font-medium">История депозитов пуста</p>
              <p className="text-[10px] text-slate-500 max-w-[200px] mx-auto leading-normal">
                Логи появятся сразу после синхронизации блоков сабграфом.
              </p>
            </div>
          )}
        </div>
      </div>

    </div>
  )
}