export const CONTRACT_ADDRESSES = {
  LENDING_POOL: '0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889' as `0x${string}`,
  GOVERNOR: '0x5FbDB2315678afecb367f032d93F642f64180aa3' as `0x${string}`, // Временный Mock-адрес для компиляции ТЗ Никиты
}

export const LENDING_POOL_ABI = [
  {
    inputs: [{ name: 'user', type: 'address' }],
    name: 'getUserAccountData',
    outputs: [
      { name: 'totalCollateralBase', type: 'uint256' },
      { name: 'totalDebtBase', type: 'uint256' },
      { name: 'availableBorrowsBase', type: 'uint256' },
      { name: 'currentLiquidationThreshold', type: 'uint256' },
      { name: 'ltv', type: 'uint256' },
      { name: 'healthFactor', type: 'uint256' }
    ],
    stateMutability: 'view',
    type: 'function'
  },
  {
    inputs: [
      { name: 'asset', type: 'address' },
      { name: 'amount', type: 'uint256' }
    ],
    name: 'deposit',
    outputs: [],
    stateMutability: 'external',
    type: 'function'
  },
  {
    inputs: [
      { name: 'asset', type: 'address' },
      { name: 'amount', type: 'uint256' }
    ],
    name: 'borrow',
    outputs: [],
    stateMutability: 'external',
    type: 'function'
  }
] as const // Обязательно as const для строгого вывода типов в viem/wagmi