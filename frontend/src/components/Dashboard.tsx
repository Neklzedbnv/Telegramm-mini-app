import { useState, useEffect } from 'react'
import { mainButton } from '@telegram-apps/sdk-react'
import { useNetworkCheck } from '../hooks/useNetworkCheck'
import { useReadContract, useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import {
  CONTRACT_ADDRESSES,
  LENDING_POOL_ABI,
  AMM_ABI,
  DEFI_TOKEN_ABI,
  GOVERNOR_ABI,
  ERC20_ABI,
  PROPOSAL_IDS,
} from '../config/contracts'
import { formatUnits, parseUnits, parseGwei } from 'viem'

// Arbitrum Sepolia base fee is ~0.01–0.02 gwei; use 0.5 gwei as safe ceiling
const GAS_FEES = {
  maxFeePerGas: parseGwei('0.5'),
  maxPriorityFeePerGas: parseGwei('0.001'),
} as const
import { useQuery } from '@tanstack/react-query'
import { fetchUserDeposits } from '../config/graphql'

const PROPOSAL_STATES = ['Pending', 'Active', 'Canceled', 'Defeated', 'Succeeded', 'Queued', 'Expired', 'Executed']

const STATE_BADGE: Record<string, string> = {
  Active:    'bg-blue-500/10 text-blue-400 border border-blue-500/20',
  Pending:   'bg-yellow-500/10 text-yellow-400 border border-yellow-500/20',
  Succeeded: 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20',
  Queued:    'bg-purple-500/10 text-purple-400 border border-purple-500/20',
  Executed:  'bg-slate-700 text-slate-300 border border-slate-600',
  Defeated:  'bg-rose-500/10 text-rose-400 border border-rose-500/20',
  Expired:   'bg-orange-500/10 text-orange-400 border border-orange-500/20',
  Canceled:  'bg-slate-800 text-slate-500 border border-slate-700',
}

export function Dashboard() {
  const { isConnected, isWrongNetwork } = useNetworkCheck()
  const { address } = useAccount()

  const { writeContract, data: hash, error: writeError, isPending, reset: resetWrite } = useWriteContract()
  const { isLoading: isMining, isSuccess: isTxSuccess } = useWaitForTransactionReceipt({ hash })

  // ── Lending reads ──────────────────────────────────────────────────────────
  const queryOpts = { enabled: !!address && !isWrongNetwork }

  const { data: hf, refetch: refetchHF } = useReadContract({
    address: CONTRACT_ADDRESSES.LENDING_POOL, abi: LENDING_POOL_ABI,
    functionName: 'healthFactor', args: address ? [address] : undefined, query: queryOpts,
  })
  const { data: collateral, refetch: refetchCol } = useReadContract({
    address: CONTRACT_ADDRESSES.LENDING_POOL, abi: LENDING_POOL_ABI,
    functionName: 'getCollateral',
    args: address ? [address, CONTRACT_ADDRESSES.USDC] : undefined, query: queryOpts,
  })
  const { data: debt, refetch: refetchDebt } = useReadContract({
    address: CONTRACT_ADDRESSES.LENDING_POOL, abi: LENDING_POOL_ABI,
    functionName: 'getDebt',
    args: address ? [address, CONTRACT_ADDRESSES.USDC] : undefined, query: queryOpts,
  })

  // USDC balance + allowance for LendingPool
  const { data: usdcBalance, refetch: refetchUsdcBal } = useReadContract({
    address: CONTRACT_ADDRESSES.USDC, abi: ERC20_ABI,
    functionName: 'balanceOf', args: address ? [address] : undefined, query: queryOpts,
  })
  const { data: usdcAllowance, refetch: refetchAllowance } = useReadContract({
    address: CONTRACT_ADDRESSES.USDC, abi: ERC20_ABI,
    functionName: 'allowance',
    args: address ? [address, CONTRACT_ADDRESSES.LENDING_POOL] : undefined, query: queryOpts,
  })

  // ── Governance reads ───────────────────────────────────────────────────────
  const { data: votingPower, refetch: refetchVP } = useReadContract({
    address: CONTRACT_ADDRESSES.DEFI_TOKEN, abi: DEFI_TOKEN_ABI,
    functionName: 'getVotes', args: address ? [address] : undefined, query: queryOpts,
  })
  const { data: delegateAddr } = useReadContract({
    address: CONTRACT_ADDRESSES.DEFI_TOKEN, abi: DEFI_TOKEN_ABI,
    functionName: 'delegates', args: address ? [address] : undefined, query: queryOpts,
  })
  const { data: dgtBalance } = useReadContract({
    address: CONTRACT_ADDRESSES.DEFI_TOKEN, abi: DEFI_TOKEN_ABI,
    functionName: 'balanceOf', args: address ? [address] : undefined, query: queryOpts,
  })

  const { data: p1StateRaw, refetch: refetchP1 } = useReadContract({
    address: CONTRACT_ADDRESSES.GOVERNOR, abi: GOVERNOR_ABI,
    functionName: 'state', args: [PROPOSAL_IDS.PIP_01], query: { enabled: !isWrongNetwork },
  })
  const { data: p2StateRaw, refetch: refetchP2 } = useReadContract({
    address: CONTRACT_ADDRESSES.GOVERNOR, abi: GOVERNOR_ABI,
    functionName: 'state', args: [PROPOSAL_IDS.PIP_02], query: { enabled: !isWrongNetwork },
  })

  // ── AMM reads ──────────────────────────────────────────────────────────────
  const { data: reservesData, refetch: refetchReserves } = useReadContract({
    address: CONTRACT_ADDRESSES.AMM, abi: AMM_ABI,
    functionName: 'getReserves', query: { enabled: !isWrongNetwork },
  })
  const { data: balanceA, refetch: refetchBalA } = useReadContract({
    address: CONTRACT_ADDRESSES.TOKEN_A, abi: ERC20_ABI,
    functionName: 'balanceOf', args: address ? [address] : undefined, query: queryOpts,
  })
  const { data: balanceB, refetch: refetchBalB } = useReadContract({
    address: CONTRACT_ADDRESSES.TOKEN_B, abi: ERC20_ABI,
    functionName: 'balanceOf', args: address ? [address] : undefined, query: queryOpts,
  })
  const { data: tknaAllowance, refetch: refetchTknaAllowance } = useReadContract({
    address: CONTRACT_ADDRESSES.TOKEN_A, abi: ERC20_ABI,
    functionName: 'allowance',
    args: address ? [address, CONTRACT_ADDRESSES.AMM] : undefined, query: queryOpts,
  })

  // ── Subgraph ───────────────────────────────────────────────────────────────
  const { data: depositHistory } = useQuery({
    queryKey: ['userDeposits', address],
    queryFn: () => fetchUserDeposits(address!),
    enabled: !!address && !isWrongNetwork,
    refetchInterval: 10000,
  })

  // ── Derived values ─────────────────────────────────────────────────────────
  const healthFactor  = hf ? parseFloat(formatUnits(hf as bigint, 18)) : 0
  const supplied      = collateral ? parseFloat(formatUnits(collateral as bigint, 6)).toFixed(2) : '0.00'
  const borrowed      = debt       ? parseFloat(formatUnits(debt      as bigint, 6)).toFixed(2) : '0.00'
  const usdcBal       = usdcBalance ? parseFloat(formatUnits(usdcBalance as bigint, 6)).toFixed(2) : '0.00'
  const vp            = votingPower ? parseFloat(formatUnits(votingPower as bigint, 18)).toFixed(2) : '0.00'
  const dgt           = dgtBalance  ? parseFloat(formatUnits(dgtBalance  as bigint, 18)).toFixed(0) : '0'
  const delegated     = delegateAddr && (delegateAddr as string) !== '0x0000000000000000000000000000000000000000'
  const delegateLabel = delegated
    ? (delegateAddr as string).toLowerCase() === address?.toLowerCase() ? 'Self' : `${(delegateAddr as string).slice(0,6)}...${(delegateAddr as string).slice(-4)}`
    : 'Not delegated'

  const reserveA = reservesData ? parseFloat(formatUnits((reservesData as readonly [bigint,bigint])[0], 18)).toLocaleString(undefined, {maximumFractionDigits:2}) : '—'
  const reserveB = reservesData ? parseFloat(formatUnits((reservesData as readonly [bigint,bigint])[1], 18)).toLocaleString(undefined, {maximumFractionDigits:2}) : '—'
  const fmtBalA  = balanceA ? parseFloat(formatUnits(balanceA as bigint, 18)).toFixed(2) : '0.00'
  const fmtBalB  = balanceB ? parseFloat(formatUnits(balanceB as bigint, 18)).toFixed(2) : '0.00'

  const proposals = [
    { id: PROPOSAL_IDS.PIP_01, title: 'PIP-01: Increase LTV for ETH collateral to 80%',       state: p1StateRaw !== undefined ? PROPOSAL_STATES[Number(p1StateRaw)] : '...' },
    { id: PROPOSAL_IDS.PIP_02, title: 'PIP-02: Integrate Chainlink oracle for Arbitrum Sepolia', state: p2StateRaw !== undefined ? PROPOSAL_STATES[Number(p2StateRaw)] : '...' },
  ]

  // ── Local UI state ─────────────────────────────────────────────────────────
  const [depositAmt,   setDepositAmt]   = useState('100')
  const [borrowAmt,    setBorrowAmt]    = useState('50')
  const [repayAmt,     setRepayAmt]     = useState('50')
  const [withdrawAmt,  setWithdrawAmt]  = useState('100')
  const [swapAmount,   setSwapAmount]   = useState('100')
  const [proposalDesc, setProposalDesc] = useState('')
  const [txLabel,    setTxLabel]    = useState('')

  // Refetch everything after successful tx
  useEffect(() => {
    if (isTxSuccess) {
      refetchHF(); refetchCol(); refetchDebt()
      refetchUsdcBal(); refetchAllowance()
      refetchVP(); refetchReserves()
      refetchBalA(); refetchBalB(); refetchTknaAllowance()
      refetchP1(); refetchP2()
    }
  }, [isTxSuccess])

  // Telegram MainButton → deposit
  useEffect(() => {
    if (isConnected && !isWrongNetwork && mainButton.mount.isAvailable()) {
      mainButton.mount()
      mainButton.setParams({
        text: isPending ? 'ПОДТВЕРДИТЕ В КОШЕЛЬКЕ...' : isMining ? 'ОБРАБОТКА...' : `ДЕПОЗИТ ${depositAmt} USDC`,
        backgroundColor: isPending || isMining ? '#475569' : '#2563eb',
        textColor: '#ffffff', isVisible: true, isEnabled: !isPending && !isMining,
      })
      const unsub = mainButton.onClick(handleDeposit)
      return () => { unsub(); mainButton.setParams({ isVisible: false }) }
    } else if (mainButton.isMounted()) {
      mainButton.setParams({ isVisible: false })
    }
  }, [isConnected, isWrongNetwork, isPending, isMining, depositAmt])

  // ── Transactions ───────────────────────────────────────────────────────────

  const handleApproveUsdc = () => {
    setTxLabel('Approve USDC')
    writeContract({
      address: CONTRACT_ADDRESSES.USDC, abi: ERC20_ABI,
      functionName: 'approve',
      args: [CONTRACT_ADDRESSES.LENDING_POOL, parseUnits('1000000', 6)],
      ...GAS_FEES,
    })
  }

  const handleDeposit = () => {
    const amount = parseUnits(depositAmt || '0', 6)
    if (amount === 0n) return
    setTxLabel(`Deposit ${depositAmt} USDC`)
    writeContract({
      address: CONTRACT_ADDRESSES.LENDING_POOL, abi: LENDING_POOL_ABI,
      functionName: 'deposit',
      args: [CONTRACT_ADDRESSES.USDC, amount],
      ...GAS_FEES,
    })
  }

  const handleBorrow = () => {
    const amount = parseUnits(borrowAmt || '0', 6)
    if (amount === 0n) return
    setTxLabel(`Borrow ${borrowAmt} USDC`)
    writeContract({
      address: CONTRACT_ADDRESSES.LENDING_POOL, abi: LENDING_POOL_ABI,
      functionName: 'borrow',
      args: [CONTRACT_ADDRESSES.USDC, amount],
      ...GAS_FEES,
    })
  }

  const handleRepay = () => {
    const amount = parseUnits(repayAmt || '0', 6)
    if (amount === 0n) return
    setTxLabel(`Repay ${repayAmt} USDC`)
    writeContract({
      address: CONTRACT_ADDRESSES.LENDING_POOL, abi: LENDING_POOL_ABI,
      functionName: 'repay',
      args: [CONTRACT_ADDRESSES.USDC, amount],
      ...GAS_FEES,
    })
  }

  const handleWithdraw = () => {
    const amount = parseUnits(withdrawAmt || '0', 6)
    if (amount === 0n) return
    setTxLabel(`Withdraw ${withdrawAmt} USDC`)
    writeContract({
      address: CONTRACT_ADDRESSES.LENDING_POOL, abi: LENDING_POOL_ABI,
      functionName: 'withdraw',
      args: [CONTRACT_ADDRESSES.USDC, amount],
      ...GAS_FEES,
    })
  }

  const handlePropose = () => {
    const desc = proposalDesc.trim()
    if (!desc || !address) return
    setTxLabel('Create proposal')
    writeContract({
      address: CONTRACT_ADDRESSES.GOVERNOR, abi: GOVERNOR_ABI,
      functionName: 'propose',
      // text-only proposal: target = zero address, value = 0, calldata = 0x
      args: [[address], [0n], ['0x'], desc],
      ...GAS_FEES,
    })
  }

  const handleDelegate = () => {
    if (!address) return
    setTxLabel('Delegate DGT to self')
    writeContract({
      address: CONTRACT_ADDRESSES.DEFI_TOKEN, abi: DEFI_TOKEN_ABI,
      functionName: 'delegate',
      args: [address],
      ...GAS_FEES,
    })
  }

  const handleVote = (proposalId: bigint, support: number) => {
    const label = ['Against','For','Abstain'][support] ?? String(support)
    setTxLabel(`Vote ${label}`)
    writeContract({
      address: CONTRACT_ADDRESSES.GOVERNOR, abi: GOVERNOR_ABI,
      functionName: 'castVote',
      args: [proposalId, support],
      ...GAS_FEES,
    })
  }

  const handleApproveSwap = () => {
    setTxLabel('Approve TKNA for AMM')
    writeContract({
      address: CONTRACT_ADDRESSES.TOKEN_A, abi: ERC20_ABI,
      functionName: 'approve',
      args: [CONTRACT_ADDRESSES.AMM, parseUnits('1000000', 18)],
      ...GAS_FEES,
    })
  }

  const handleSwap = () => {
    const amountIn = parseUnits(swapAmount || '0', 18)
    if (amountIn === 0n) return
    setTxLabel(`Swap ${swapAmount} TKNA`)
    writeContract({
      address: CONTRACT_ADDRESSES.AMM, abi: AMM_ABI,
      functionName: 'swap',
      args: [CONTRACT_ADDRESSES.TOKEN_A, amountIn, 0n],
      ...GAS_FEES,
    })
  }

  const needsUsdcApprove = (usdcAllowance as bigint ?? 0n) < parseUnits(depositAmt || '0', 6)
  const needsTknaApprove = (tknaAllowance as bigint ?? 0n) < parseUnits(swapAmount || '0', 18)
  const btnDisabled = isPending || isMining

  // ── Health Factor style ────────────────────────────────────────────────────
  const hfStyle = () => {
    if (healthFactor === 0) return 'text-slate-400 border-slate-800/80 bg-slate-900/40'
    if (healthFactor > 2)   return 'text-emerald-400 border-emerald-500/20 bg-emerald-500/5 shadow-emerald-500/5'
    if (healthFactor > 1.1) return 'text-amber-400 border-amber-500/20 bg-amber-500/5'
    return 'text-red-400 border-red-500/20 bg-red-500/5 animate-pulse'
  }

  // ── Not connected ──────────────────────────────────────────────────────────
  if (!isConnected || isWrongNetwork) {
    return (
      <div className="min-h-[80vh] flex items-center justify-center p-4">
        <div className="w-full max-w-sm p-6 bg-slate-900/60 backdrop-blur-xl rounded-3xl border border-slate-800/60 text-center space-y-4">
          <div className="w-12 h-12 rounded-full bg-blue-500/10 border border-blue-500/20 flex items-center justify-center mx-auto text-blue-400 text-lg">⚡</div>
          <div className="space-y-1.5">
            <h3 className="text-sm font-bold text-slate-200">Требуется авторизация</h3>
            <p className="text-xs text-slate-400 leading-relaxed px-4">
              Подключите кошелёк на Arbitrum Sepolia для доступа к DeFi позициям и голосованию DAO.
            </p>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="relative space-y-5 pb-24 px-1 select-none">
      <div className="absolute top-[-10%] left-[-20%] w-64 h-64 bg-blue-600/10 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-[30%] right-[-20%] w-72 h-72 bg-emerald-600/5 rounded-full blur-3xl pointer-events-none" />

      {/* TX status */}
      {(hash || writeError) && (
        <div className="p-3.5 bg-slate-900/80 backdrop-blur-md rounded-2xl border border-slate-800/80 text-xs font-mono space-y-2 shadow-lg">
          <div className="flex items-center justify-between border-b border-slate-800/60 pb-1.5">
            <span className="text-slate-400 font-sans font-semibold">{txLabel}</span>
            {hash && (
              <a href={`https://sepolia.arbiscan.io/tx/${hash}`} target="_blank" rel="noreferrer"
                className="text-blue-400 hover:underline text-[10px]">Explorer ↗</a>
            )}
          </div>
          {hash && <p className="text-slate-500 truncate"><span className="text-slate-600">Hash: </span>{hash}</p>}
          {isMining   && <p className="text-amber-400 flex items-center gap-1.5"><span className="w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse" />Майнинг...</p>}
          {isTxSuccess && <p className="text-emerald-400 flex items-center gap-1.5"><span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />✓ Подтверждено!</p>}
          {writeError  && (
            <p className="text-rose-400 flex items-start gap-1.5">
              <span>⚠️</span>
              <span>{(writeError as {shortMessage?:string; message?:string}).shortMessage || (writeError as {message?:string}).message || 'Отклонено'}</span>
            </p>
          )}
          {(isTxSuccess || writeError) && (
            <button onClick={resetWrite} className="text-[10px] text-slate-500 hover:text-slate-300 transition-colors">Закрыть ×</button>
          )}
        </div>
      )}

      {/* ── Health Factor ── */}
      <div className={`p-4 rounded-2xl border flex items-center justify-between backdrop-blur-md shadow-lg ${hfStyle()}`}>
        <div className="space-y-0.5">
          <h4 className="text-[10px] uppercase font-bold tracking-wider text-slate-400">Health Factor</h4>
          <p className="text-2xl font-black tracking-tight">
            {healthFactor === 0 ? '—' : healthFactor > 100 ? '∞' : healthFactor.toFixed(2)}
          </p>
        </div>
        <div className="text-right">
          {healthFactor === 0
            ? <span className="text-[10px] px-2 py-0.5 rounded-md bg-slate-800 text-slate-400 border border-slate-700/50">No Active Loans</span>
            : healthFactor > 1.1
            ? <span className="text-[10px] px-2 py-0.5 rounded-md bg-emerald-500/10 text-emerald-400 font-bold border border-emerald-500/20">✓ Safe</span>
            : <span className="text-[10px] px-2 py-0.5 rounded-md bg-rose-500/10 text-rose-400 font-bold border border-rose-500/20 animate-bounce">⚠️ At Risk</span>
          }
          <p className="text-[10px] text-slate-500 mt-1">Liq. threshold &lt; 1.0</p>
        </div>
      </div>

      {/* ── Lending ── */}
      <div className="bg-slate-900/40 backdrop-blur-md p-4 rounded-2xl border border-slate-800/60 space-y-3.5 shadow-md">
        <div className="flex items-center justify-between">
          <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider">Lending Pool</h3>
          <span className="text-[9px] px-2 py-0.5 rounded-full bg-blue-500/10 text-blue-400 border border-blue-500/20 font-bold">USDC</span>
        </div>

        {/* Balances */}
        <div className="grid grid-cols-3 gap-2 text-xs">
          {[
            { label: 'Wallet', value: usdcBal, unit: 'USDC', color: 'text-slate-200' },
            { label: 'Supplied', value: supplied, unit: 'USDC', color: 'text-blue-400' },
            { label: 'Borrowed', value: borrowed, unit: 'USDC', color: 'text-purple-400' },
          ].map(({ label, value, unit, color }) => (
            <div key={label} className="p-2.5 bg-slate-950/40 rounded-xl border border-slate-900/60">
              <p className="text-slate-500 text-[10px] mb-1">{label}</p>
              <p className={`font-mono font-bold ${color}`}>{value} <span className="text-[9px]">{unit}</span></p>
            </div>
          ))}
        </div>

        {/* Deposit */}
        <div className="space-y-2">
          <p className="text-[10px] text-slate-500">Deposit USDC as collateral</p>
          <div className="flex gap-2">
            <input type="number" value={depositAmt} onChange={e => setDepositAmt(e.target.value)}
              placeholder="Amount USDC"
              className="flex-1 px-3 py-2 bg-slate-950/60 border border-slate-800/80 rounded-xl text-xs text-slate-200 placeholder-slate-600 focus:outline-none focus:border-blue-500/40" />
            {needsUsdcApprove
              ? <button onClick={handleApproveUsdc} disabled={btnDisabled}
                  className="px-4 py-2 bg-amber-600/80 hover:bg-amber-600 text-white rounded-xl text-xs font-bold transition-all disabled:opacity-30">
                  Approve
                </button>
              : <button onClick={handleDeposit} disabled={btnDisabled}
                  className="px-4 py-2 bg-blue-600/80 hover:bg-blue-600 text-white rounded-xl text-xs font-bold transition-all disabled:opacity-30">
                  {btnDisabled ? '...' : 'Deposit'}
                </button>
            }
          </div>
        </div>

        {/* Borrow */}
        <div className="space-y-2">
          <p className="text-[10px] text-slate-500">Borrow USDC against collateral</p>
          <div className="flex gap-2">
            <input type="number" value={borrowAmt} onChange={e => setBorrowAmt(e.target.value)}
              placeholder="Amount USDC"
              className="flex-1 px-3 py-2 bg-slate-950/60 border border-slate-800/80 rounded-xl text-xs text-slate-200 placeholder-slate-600 focus:outline-none focus:border-purple-500/40" />
            <button onClick={handleBorrow} disabled={btnDisabled}
              className="px-4 py-2 bg-purple-600/80 hover:bg-purple-600 text-white rounded-xl text-xs font-bold transition-all disabled:opacity-30">
              {btnDisabled ? '...' : 'Borrow'}
            </button>
          </div>
        </div>

        <div className="space-y-2">
          <p className="text-[10px] text-slate-500">Repay borrowed USDC</p>
          <div className="flex gap-2">
            <input type="number" value={repayAmt} onChange={e => setRepayAmt(e.target.value)}
              placeholder="Amount USDC"
              className="flex-1 px-3 py-2 bg-slate-950/60 border border-slate-800/80 rounded-xl text-xs text-slate-200 placeholder-slate-600 focus:outline-none focus:border-emerald-500/40" />
            <button onClick={handleRepay} disabled={btnDisabled}
              className="px-4 py-2 bg-emerald-600/80 hover:bg-emerald-600 text-white rounded-xl text-xs font-bold transition-all disabled:opacity-30">
              {btnDisabled ? '...' : 'Repay'}
            </button>
          </div>
        </div>

        <div className="space-y-2">
          <p className="text-[10px] text-slate-500">Withdraw collateral</p>
          <div className="flex gap-2">
            <input type="number" value={withdrawAmt} onChange={e => setWithdrawAmt(e.target.value)}
              placeholder="Amount USDC"
              className="flex-1 px-3 py-2 bg-slate-950/60 border border-slate-800/80 rounded-xl text-xs text-slate-200 placeholder-slate-600 focus:outline-none focus:border-orange-500/40" />
            <button onClick={handleWithdraw} disabled={btnDisabled}
              className="px-4 py-2 bg-orange-600/80 hover:bg-orange-600 text-white rounded-xl text-xs font-bold transition-all disabled:opacity-30">
              {btnDisabled ? '...' : 'Withdraw'}
            </button>
          </div>
        </div>
      </div>

      {/* ── Governance ── */}
      <div className="bg-slate-900/40 backdrop-blur-md p-4 rounded-2xl border border-slate-800/60 space-y-3.5 shadow-md">
        <div className="flex items-center justify-between">
          <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider">DAO Governance</h3>
          <span className="text-[9px] px-2 py-0.5 rounded-full bg-blue-500/10 text-blue-400 border border-blue-500/20 font-bold">OZ Governor</span>
        </div>

        {/* Voting power */}
        <div className="grid grid-cols-3 gap-2 text-xs">
          <div className="p-2.5 bg-slate-950/40 rounded-xl border border-slate-900/60">
            <p className="text-slate-500 text-[10px] mb-1">DGT Balance</p>
            <p className="text-slate-200 font-mono font-bold">{dgt}</p>
          </div>
          <div className="p-2.5 bg-slate-950/40 rounded-xl border border-slate-900/60">
            <p className="text-slate-500 text-[10px] mb-1">Voting Power</p>
            <p className="text-blue-400 font-mono font-bold">{vp}</p>
          </div>
          <div className="p-2.5 bg-slate-950/40 rounded-xl border border-slate-900/60">
            <p className="text-slate-500 text-[10px] mb-1">Delegate</p>
            <p className={`font-mono font-bold text-[11px] ${delegated ? 'text-emerald-400' : 'text-slate-500'}`}>{delegateLabel}</p>
          </div>
        </div>

        {/* Delegate button */}
        {!delegated && (
          <button onClick={handleDelegate} disabled={btnDisabled}
            className="w-full py-2 bg-blue-600/20 hover:bg-blue-600/30 border border-blue-500/20 text-blue-400 rounded-xl text-xs font-bold transition-all disabled:opacity-30">
            {btnDisabled ? '...' : '⚡ Activate Voting Power (Self-delegate DGT)'}
          </button>
        )}

        {/* Proposals */}
        <div className="space-y-2.5">
          {proposals.map((prop) => (
            <div key={String(prop.id)} className="p-3 bg-slate-950/40 rounded-xl border border-slate-900 space-y-3">
              <div className="flex items-start justify-between gap-3">
                <p className="text-xs font-semibold text-slate-200 leading-relaxed">{prop.title}</p>
                <span className={`text-[9px] px-2 py-0.5 font-bold rounded-md shrink-0 ${STATE_BADGE[prop.state] ?? 'bg-slate-800 text-slate-400 border border-slate-700'}`}>
                  {prop.state}
                </span>
              </div>
              {prop.state === 'Active' && (
                <div className="grid grid-cols-3 gap-2">
                  {([['За', 1, 'emerald'], ['Против', 0, 'rose'], ['Воздерж.', 2, 'slate']] as const).map(([label, val, color]) => (
                    <button key={val} onClick={() => handleVote(prop.id, val)} disabled={btnDisabled}
                      className={`py-1.5 rounded-lg text-[11px] font-bold border transition-all disabled:opacity-30
                        bg-${color}-500/5 hover:bg-${color}-500/10 text-${color}-400 border-${color}-500/10`}>
                      {label}
                    </button>
                  ))}
                </div>
              )}
              {prop.state === 'Pending' && (
                <p className="text-[10px] text-yellow-400/70">Voting starts after ~7200 blocks (~30 min)</p>
              )}
            </div>
          ))}
        </div>

        {/* Create proposal */}
        <div className="space-y-2 pt-1">
          <p className="text-[10px] text-slate-500 font-semibold uppercase tracking-wide">Create new proposal</p>
          <textarea
            value={proposalDesc}
            onChange={e => setProposalDesc(e.target.value)}
            placeholder="Describe your proposal (e.g. PIP-03: Adjust liquidation penalty to 8%)"
            rows={3}
            className="w-full px-3 py-2 bg-slate-950/60 border border-slate-800/80 rounded-xl text-xs text-slate-200 placeholder-slate-600 focus:outline-none focus:border-blue-500/40 resize-none"
          />
          <button
            onClick={handlePropose}
            disabled={btnDisabled || !proposalDesc.trim() || !delegated}
            className="w-full py-2 bg-blue-600/80 hover:bg-blue-600 text-white rounded-xl text-xs font-bold transition-all disabled:opacity-30"
          >
            {btnDisabled ? '...' : 'Submit Proposal'}
          </button>
          {!delegated && (
            <p className="text-[10px] text-yellow-400/70">You must delegate DGT first to create proposals</p>
          )}
        </div>
      </div>

      {/* ── The Graph history ── */}
      <div className="bg-slate-900/40 backdrop-blur-md p-4 rounded-2xl border border-slate-800/60 space-y-3.5 shadow-md">
        <div className="flex items-center justify-between">
          <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider">История операций</h3>
          <span className="text-[9px] px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-bold">The Graph</span>
        </div>
        <div className="space-y-2 max-h-[180px] overflow-y-auto">
          {depositHistory && depositHistory.length > 0 ? (
            depositHistory.map((tx) => (
              <div key={tx.id} className="p-3 bg-slate-950/40 rounded-xl border border-slate-900/60 flex items-center justify-between text-xs">
                <div className="space-y-0.5">
                  <p className="text-emerald-400 font-bold flex items-center gap-1"><span>↓</span> Deposit</p>
                  <p className="text-[10px] text-slate-500 font-mono">
                    {new Date(parseInt(tx.timestamp) * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                  </p>
                </div>
                <p className="text-slate-100 font-black">
                  {parseFloat(formatUnits(BigInt(tx.amount), 6)).toFixed(2)} <span className="text-[10px] text-blue-400">USDC</span>
                </p>
              </div>
            ))
          ) : (
            <div className="py-6 text-center border border-dashed border-slate-800/60 rounded-xl">
              <p className="text-xs text-slate-400">История пуста</p>
              <p className="text-[10px] text-slate-500 mt-1">Появится после синхронизации субграфа</p>
            </div>
          )}
        </div>
      </div>

      {/* ── AMM Swap ── */}
      <div className="bg-slate-900/40 backdrop-blur-md p-4 rounded-2xl border border-slate-800/60 space-y-3.5 shadow-md">
        <div className="flex items-center justify-between">
          <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider">AMM Swap</h3>
          <span className="text-[9px] px-2 py-0.5 rounded-full bg-blue-500/10 text-blue-400 border border-blue-500/20 font-bold">x·y=k</span>
        </div>

        {/* Reserves */}
        <div className="grid grid-cols-2 gap-2 text-xs">
          {[['Reserve A', reserveA, 'TKNA'], ['Reserve B', reserveB, 'TKNB']].map(([label, val, unit]) => (
            <div key={label} className="p-2.5 bg-slate-950/40 rounded-xl border border-slate-900/60">
              <p className="text-slate-500 text-[10px] mb-1">{label}</p>
              <p className="text-slate-400 font-mono text-[10px]">{val} <span className="text-[9px]">{unit}</span></p>
            </div>
          ))}
        </div>

        {/* User balances */}
        <div className="grid grid-cols-2 gap-2 text-xs">
          {[['Your TKNA', fmtBalA, 'text-blue-400'], ['Your TKNB', fmtBalB, 'text-emerald-400']].map(([label, val, color]) => (
            <div key={label} className="p-2.5 bg-slate-950/40 rounded-xl border border-slate-900/60">
              <p className="text-slate-500 text-[10px] mb-1">{label}</p>
              <p className={`font-mono font-bold ${color}`}>{val}</p>
            </div>
          ))}
        </div>

        {/* Swap input */}
        <div className="space-y-2">
          <p className="text-[10px] text-slate-500">Swap TKNA → TKNB (0.3% fee)</p>
          <div className="flex gap-2">
            <input type="number" value={swapAmount} onChange={e => setSwapAmount(e.target.value)}
              placeholder="Amount TKNA"
              className="flex-1 px-3 py-2 bg-slate-950/60 border border-slate-800/80 rounded-xl text-xs text-slate-200 placeholder-slate-600 focus:outline-none focus:border-blue-500/40" />
            {needsTknaApprove
              ? <button onClick={handleApproveSwap} disabled={btnDisabled}
                  className="px-4 py-2 bg-amber-600/80 hover:bg-amber-600 text-white rounded-xl text-xs font-bold transition-all disabled:opacity-30">
                  Approve
                </button>
              : <button onClick={handleSwap} disabled={btnDisabled}
                  className="px-4 py-2 bg-blue-600/80 hover:bg-blue-600 text-white rounded-xl text-xs font-bold transition-all disabled:opacity-30">
                  {btnDisabled ? '...' : 'Swap'}
                </button>
            }
          </div>
        </div>
      </div>

    </div>
  )
}
