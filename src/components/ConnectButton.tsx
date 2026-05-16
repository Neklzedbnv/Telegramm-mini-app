import { useWeb3Modal } from '@web3modal/wagmi/react'
import { useNetworkCheck } from '../hooks/useNetworkCheck'

export function ConnectButton() {
  const { open } = useWeb3Modal()
  const { isConnected, address, isWrongNetwork, switchToCorrectNetwork } = useNetworkCheck()

  const formatAddress = (addr: string | undefined) => {
    if (!addr) return ''
    return `${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}`
  }

  if (!isConnected) {
    return (
      <button
        onClick={() => open()}
        className="w-full py-3 px-4 bg-tgButton text-tgButtonText font-bold rounded-2xl shadow-lg hover:opacity-90 active:scale-[0.98] transition-all duration-150"
      >
        Connect Wallet
      </button>
    )
  }

  if (isWrongNetwork) {
    return (
      <button
        onClick={switchToCorrectNetwork}
        className="w-full py-3 px-4 bg-red-600 text-white font-black rounded-2xl shadow-lg hover:bg-red-700 animate-pulse active:scale-[0.98] transition-all duration-150"
      >
        ⚠️ Switch to L2 Network
      </button>
    )
  }

  return (
    <button
      onClick={() => open({ view: 'Account' })}
      className="w-full py-3 px-4 bg-tgSecondaryBg border border-slate-800 text-tgText font-mono rounded-2xl shadow-md hover:bg-slate-900 active:scale-[0.98] transition-all duration-150 flex items-center justify-center space-x-2"
    >
      <span className="h-2 w-2 rounded-full bg-emerald-500" />
      <span>{formatAddress(address)}</span>
    </button>
  )
}