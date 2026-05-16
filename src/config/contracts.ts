// Адреса твоих смарт-контрактов в L2 тестнете
export const CONTRACT_ADDRESSES = {
  LENDING_POOL: '0x0000000000000000000000000000000000000000' as `0x${string}`, // Вставь сюда свой адрес контракта
}

// Минимальный ABI для чтения состояния позиций пользователя и выполнения транзакций
export const LENDING_POOL_ABI = [
  {
    inputs: [{ internalType: 'address', name: 'user', type: 'address' }],
    name: 'getUserAccountData',
    outputs: [
      { internalType: 'uint256', name: 'totalCollateralBase', type: 'uint256' },
      { internalType: 'uint256', name: 'totalDebtBase', type: 'uint256' },
      { internalType: 'uint256', name: 'availableBorrowsBase', type: 'uint256' },
      { internalType: 'uint256', name: 'currentLiquidationThreshold', type: 'uint256' },
      { internalType: 'uint256', name: 'ltv', type: 'uint256' },
      { internalType: 'uint256', name: 'healthFactor', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { internalType: 'address', name: 'asset', type: 'address' },
      { internalType: 'uint256', name: 'amount', type: 'uint256' },
    ],
    name: 'deposit',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  }
] as const // const кастинг обязателен для автокомплита типов в Wagmi v2