# Task: Concurrent Inventory Bug Fix

## Overview

**Difficulty**: Very Hard
**Domain**: Backend Engineering / Concurrency
**Application**: Eclipse IDE with Maven Java project

A backend engineer must identify and fix all thread-safety violations in a high-traffic inventory service, then add multi-threaded verification tests.

## Goal

Fix ALL four thread-safety bugs in `inventory-service` and add concurrent JUnit 5 tests.

### Bugs to Fix

1. **StockCounter** (`StockCounter.java`): Uses plain `int` fields — not thread-safe under concurrent increment. Replace with `AtomicInteger` from `java.util.concurrent.atomic`.

2. **ProductCatalog** (`ProductCatalog.java`): Uses `HashMap` which is not thread-safe under concurrent reads/writes. Replace with `ConcurrentHashMap`.

3. **InventoryManager** (`InventoryManager.java`): Two problems:
   - Uses `HashMap` (not thread-safe) — replace with `ConcurrentHashMap`
   - `removeStock()` has a non-atomic check-then-act: reads current stock, checks if sufficient, then writes new value as separate operations. Fix by making the entire operation atomic using `ConcurrentHashMap.compute()` or a `synchronized` block.

4. **ReservationService** (`ReservationService.java`): `createReservation()` and `cancelReservation()` operate on two separate maps (`reservedQuantities` + `activeReservationIds`) without synchronization. Fix by synchronizing these compound operations.

## Success Criteria

- `StockCounter` uses `AtomicInteger` (and/or `synchronized`)
- `ProductCatalog` uses `ConcurrentHashMap`
- `InventoryManager` uses `ConcurrentHashMap` and atomic `removeStock()`
- `ReservationService` has synchronized compound operations
- At least 2 new JUnit 5 test files with multi-threaded tests (using `ExecutorService` or `Thread`)
- `mvn clean test` passes

## Verification Strategy

1. Gate: if NO `java.util.concurrent` usage found → score=0
2. StockCounter uses AtomicInteger (10 pts)
3. ProductCatalog uses ConcurrentHashMap (10 pts)
4. InventoryManager uses ConcurrentHashMap with atomic removeStock (10 pts)
5. ReservationService is synchronized (10 pts)
6. Concurrent tests present (ExecutorService/Thread/CountDownLatch) (20 pts) — 2 pts per test file over initial count
7. All four concurrent primitives used somewhere (30 pts)
8. Build + tests pass (10 pts)

Pass threshold: 70/100
