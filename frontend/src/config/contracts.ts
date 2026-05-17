export const CONTRACT_ADDRESSES = {
  LENDING_POOL: '0xC047D3248eE6F4D5ba570d8cD8D904C2D3a0A9F9' as `0x${string}`,
  GOVERNOR:     '0xA2F72eB781dCD791F95E4c0E4bb26DCF11a94a6C' as `0x${string}`,
  DEFI_TOKEN:   '0x3516c36c76D19Cb3fBc81B5EfFdbD11aa89BaDF4' as `0x${string}`,
  AMM:          '0xaE4b7dcF92c69E85B2B203Ac2054D6Bb67533b5B' as `0x${string}`,
  TOKEN_A:      '0x0Ca55915D0308D968EeEa4BEa57B6E507B7a086D' as `0x${string}`,
  TOKEN_B:      '0x840e571542CEd2C79Cac03c6aaFe6d3EC3494985' as `0x${string}`,
  USDC:         '0xD82cdA9de4a95B12913FCf935E3c5fFbD0B47D9C' as `0x${string}`,
}

// Real on-chain proposal IDs (created via CreateProposalStep2.s.sol)
export const PROPOSAL_IDS = {
  PIP_01: 65245196053914517598729806484549020432560168588904868101510700262055355961775n,
  PIP_02: 106341771772600122459286142138393075980060908720998186349036931704520978779337n,
}

export const ERC20_ABI = [
  {
    inputs: [{ name: 'account', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount',  type: 'uint256' },
    ],
    name: 'approve',
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'owner',   type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    name: 'allowance',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const

export const LENDING_POOL_ABI = [
  // ── reads ──────────────────────────────────────────────────────────────────
  {
    inputs: [{ name: 'user', type: 'address' }],
    name: 'healthFactor',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'user',  type: 'address' },
      { name: 'token', type: 'address' },
    ],
    name: 'getCollateral',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'user',  type: 'address' },
      { name: 'token', type: 'address' },
    ],
    name: 'getDebt',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  // ── writes ─────────────────────────────────────────────────────────────────
  {
    inputs: [
      { name: 'token',  type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'deposit',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'token',  type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'borrow',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'token',  type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'repay',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'token',  type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'withdraw',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
] as const

export const DEFI_TOKEN_ABI = [
  {
    inputs: [{ name: 'account', type: 'address' }],
    name: 'getVotes',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'account', type: 'address' }],
    name: 'delegates',
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'account', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'delegatee', type: 'address' }],
    name: 'delegate',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
] as const

export const GOVERNOR_ABI = [
  {
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    name: 'state',
    outputs: [{ name: '', type: 'uint8' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'proposalId', type: 'uint256' },
      { name: 'support',    type: 'uint8'   },
    ],
    name: 'castVote',
    outputs: [{ name: 'weight', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
] as const

export const AMM_ABI = [
  {
    inputs: [
      { name: 'amountADesired', type: 'uint256' },
      { name: 'amountBDesired', type: 'uint256' },
    ],
    name: 'addLiquidity',
    outputs: [{ name: 'shares', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'shares',    type: 'uint256' },
      { name: 'minAmountA', type: 'uint256' },
      { name: 'minAmountB', type: 'uint256' },
    ],
    name: 'removeLiquidity',
    outputs: [
      { name: 'amountA', type: 'uint256' },
      { name: 'amountB', type: 'uint256' },
    ],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'tokenIn',     type: 'address' },
      { name: 'amountIn',    type: 'uint256' },
      { name: 'minAmountOut', type: 'uint256' },
    ],
    name: 'swap',
    outputs: [{ name: 'amountOut', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'tokenIn',  type: 'address' },
      { name: 'amountIn', type: 'uint256' },
    ],
    name: 'getAmountOut',
    outputs: [{ name: 'amountOut', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getReserves',
    outputs: [
      { name: '_reserveA', type: 'uint256' },
      { name: '_reserveB', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
] as const
