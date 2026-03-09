# Task: trading_order_book_optimization

**Difficulty:** Very Hard
**Domain:** Finance / Trading Systems
**Environment:** IntelliJ IDEA (intellij_idea_env)

## Overview

A limit-order trading engine implementing price-time priority matching has a failing test suite. Bugs are spread across three files: `Order.java`, `OrderBook.java`, and `MatchingEngine.java`. The Javadoc on each class describes the correct behaviour.

## What the agent must do

1. Open the `trading-orderbook` project in IntelliJ IDEA
2. Run `OrderBookTest` and examine the failures
3. Diagnose the bugs from test failures and Javadoc
4. Fix **all three bugs** without modifying the test file

## Bugs (hidden from agent)

| # | File | Bug | Test that catches it |
|---|------|-----|---------------------|
| 1 | `OrderBook.java` | `addBid()`/`addAsk()` append to an unsorted `ArrayList` — `getBestBid()` and `getBestAsk()` return the first-inserted order, not the most aggressive price | `testBestBidIsHighestPrice`, `testBestAskIsLowestPrice` |
| 2 | `MatchingEngine.java` | Price-cross check uses strict `>` — orders at identical prices are never matched | `testAtParPriceOrdersAreMatched` |
| 3 | `Order.java` | `fillQuantity()` decrements `orderedQuantity` (should be immutable) — `getRemainingQuantity()` returns a value 2× lower than the actual remaining | `testPartialFillTracksRemainingCorrectly` |

## Scoring

| Criterion | Points |
|-----------|--------|
| OrderBook maintains sorted order (Bug 1) | 30 |
| MatchingEngine uses >= (Bug 2) | 25 |
| Order.fillQuantity() immutable orderedQuantity (Bug 3) | 25 |
| All 6 tests pass | 10 |
| Test file unmodified | 5 |
| VLM bonus | 5 |
| **Total** | **100** |

**Pass threshold:** ≥ 70 points AND all 6 tests pass
