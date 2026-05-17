import { useWeb3Modal } from '@web3modal/wagmi/react'
import { useNetworkCheck } from '../hooks/useNetworkCheck'

export function ConnectButton() {
  const { open } = useWeb3Modal()
  const { isConnected, address, isWrongNetwork, switchToCorrectNetwork } = useNetworkCheck()

  const formatAddress = (addr: string | undefined) => {
    if (!addr) return ''
    return `${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}`
  }

  // СОСТОЯНИЕ 1: Кошелек не подключен
  if (!isConnected) {
    return (
      <button
        onClick={() => open()}
        className="text-xs font-sans bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-500 hover:to-indigo-500 text-white font-bold px-4 py-2.5 rounded-xl transition-all duration-200 shadow-md shadow-blue-500/10 active:scale-[0.96] flex items-center gap-1.5"
      >
        <span>🌐</span> Connect Wallet
      </button>
    )
  }

  // СОСТОЯНИЕ 2: Подключена неверная сеть (L1 вместо нужного L2)
  if (isWrongNetwork) {
    return (
      <button
        onClick={switchToCorrectNetwork}
        className="text-xs font-sans bg-gradient-to-r from-rose-600 to-red-600 hover:from-rose-500 hover:to-red-500 text-white font-black px-4 py-2.5 rounded-xl transition-all duration-200 shadow-lg shadow-red-950/40 animate-pulse active:scale-[0.96] flex items-center gap-1.5 border border-red-500/30"
      >
        <span>⚠️</span> Switch to L2
      </button>
    )
  }

  // СОСТОЯНИЕ 3: Успешное подключение к нужной L2 сети
  return (
    <button
      onClick={() => open({ view: 'Account' })}
      className="text-xs font-mono bg-slate-900/80 backdrop-blur-md border border-slate-800 text-slate-200 px-3.5 py-2.5 rounded-xl transition-all duration-200 active:scale-[0.96] flex items-center justify-center space-x-2 shadow-inner hover:bg-slate-800 hover:border-slate-700/80"
    >
      <span className="relative flex h-2 w-2">
        <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
        <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
      </span>
      <span className="tracking-tight">{formatAddress(address)}</span>
    </button>
  )
}