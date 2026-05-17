export const CONTRACT_ADDRESSES = {
  LENDING_POOL: '0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889' as `0x${string}`,
  GOVERNOR: '0x5FbDB2315678afecb367f032d93F642f64180aa3' as `0x${string}`,
  AMM: '0x0000000000000000000000000000000000000000' as `0x${string}`, // replace after deploy
  TOKEN_A: '0x0000000000000000000000000000000000000000' as `0x${string}`,
  TOKEN_B: '0x0000000000000000000000000000000000000000' as `0x${string}`,
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
] as const

export const AMM_ABI = [
  {
    inputs: [
      { name: 'amountADesired', type: 'uint256' },
      { name: 'amountBDesired', type: 'uint256' }
    ],
    name: 'addLiquidity',
    outputs: [{ name: 'shares', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function'
  },
  {
    inputs: [
      { name: 'shares', type: 'uint256' },
      { name: 'minAmountA', type: 'uint256' },
      { name: 'minAmountB', type: 'uint256' }
    ],
    name: 'removeLiquidity',
    outputs: [
      { name: 'amountA', type: 'uint256' },
      { name: 'amountB', type: 'uint256' }
    ],
    stateMutability: 'nonpayable',
    type: 'function'
  },
  {
    inputs: [
      { name: 'tokenIn', type: 'address' },
      { name: 'amountIn', type: 'uint256' },
      { name: 'minAmountOut', type: 'uint256' }
    ],
    name: 'swap',
    outputs: [{ name: 'amountOut', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function'
  },
  {
    inputs: [
      { name: 'tokenIn', type: 'address' },
      { name: 'amountIn', type: 'uint256' }
    ],
    name: 'getAmountOut',
    outputs: [{ name: 'amountOut', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function'
  },
  {
    inputs: [],
    name: 'getReserves',
    outputs: [
      { name: '_reserveA', type: 'uint256' },
      { name: '_reserveB', type: 'uint256' }
    ],
    stateMutability: 'view',
    type: 'function'
  },
  {
    inputs: [{ name: '', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function'
  }
] as const