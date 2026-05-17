import { useAccount, useSwitchChain } from 'wagmi'
import { chains } from '../config/web3'

export function useNetworkCheck() {
  const { address, isConnected, chainId } = useAccount()
  const { switchChain } = useSwitchChain()

  // Проверяем, совпадает ли текущий chainId с одной из разрешенных нами L2 сетей
  const isWrongNetwork = isConnected && !chains.some((c) => c.id === chainId)

  // Функция для принудительного переключения на дефолтную сеть (Arbitrum Sepolia)
  const switchToCorrectNetwork = () => {
    if (switchChain) {
      switchChain({ chainId: chains[0].id })
    }
  }

  return {
    address,
    isConnected,
    isWrongNetwork,
    switchToCorrectNetwork,
    supportedChains: chains,
  }
}