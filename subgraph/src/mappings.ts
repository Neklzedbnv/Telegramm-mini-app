import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  Deposited as DepositedEvent,
  Borrowed as BorrowedEvent,
  Repaid as RepaidEvent,
  Liquidated as LiquidatedEvent,
} from "../generated/LendingPoolV1/LendingPoolV1";
import { Deposit, Borrow, Repay, Liquidation, UserPosition } from "../generated/schema";

function getOrCreatePosition(user: Bytes, timestamp: BigInt): UserPosition {
  let pos = UserPosition.load(user);
  if (pos == null) {
    pos = new UserPosition(user);
    pos.totalDeposited = BigInt.zero();
    pos.totalBorrowed = BigInt.zero();
    pos.totalRepaid = BigInt.zero();
    pos.liquidationCount = 0;
    pos.lastActivityTimestamp = timestamp;
  }
  return pos as UserPosition;
}

export function handleDeposited(event: DepositedEvent): void {
  let entity = new Deposit(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.user = event.params.user;
  entity.token = event.params.token;
  entity.amount = event.params.amount;
  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;
  entity.save();

  let pos = getOrCreatePosition(event.params.user, event.block.timestamp);
  pos.totalDeposited = pos.totalDeposited.plus(event.params.amount);
  pos.lastActivityTimestamp = event.block.timestamp;
  pos.save();
}

export function handleBorrowed(event: BorrowedEvent): void {
  let entity = new Borrow(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.user = event.params.user;
  entity.token = event.params.token;
  entity.amount = event.params.amount;
  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;
  entity.save();

  let pos = getOrCreatePosition(event.params.user, event.block.timestamp);
  pos.totalBorrowed = pos.totalBorrowed.plus(event.params.amount);
  pos.lastActivityTimestamp = event.block.timestamp;
  pos.save();
}

export function handleRepaid(event: RepaidEvent): void {
  let entity = new Repay(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.user = event.params.user;
  entity.token = event.params.token;
  entity.amount = event.params.amount;
  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;
  entity.save();

  let pos = getOrCreatePosition(event.params.user, event.block.timestamp);
  pos.totalRepaid = pos.totalRepaid.plus(event.params.amount);
  pos.lastActivityTimestamp = event.block.timestamp;
  pos.save();
}

export function handleLiquidated(event: LiquidatedEvent): void {
  let entity = new Liquidation(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.liquidator = event.params.liquidator;
  entity.borrower = event.params.borrower;
  entity.collateralToken = event.params.collateralToken;
  entity.debtToken = event.params.debtToken;
  entity.debtRepaid = event.params.debtRepaid;
  entity.collateralSeized = event.params.collateralSeized;
  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;
  entity.save();

  let pos = getOrCreatePosition(event.params.borrower, event.block.timestamp);
  pos.liquidationCount = pos.liquidationCount + 1;
  pos.lastActivityTimestamp = event.block.timestamp;
  pos.save();
}
