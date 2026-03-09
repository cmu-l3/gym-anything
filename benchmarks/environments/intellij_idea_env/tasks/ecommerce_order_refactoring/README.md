# Task: ecommerce_order_refactoring

**Difficulty:** Very Hard
**Domain:** Retail / E-Commerce
**Environment:** IntelliJ IDEA (intellij_idea_env)

## Overview

An e-commerce order processing service has a failing test suite. All bugs are in `OrderManager.java`, which handles discount calculation, total computation, and payment validation. The business rules are documented in the Javadoc of each method.

## What the agent must do

1. Open the `ecommerce-service` project in IntelliJ IDEA
2. Run `OrderManagerTest` and read the failure messages
3. Diagnose the bugs in `OrderManager.java` from the test failures and method Javadoc
4. Fix **all three bugs** without modifying the test file

## Bugs (hidden from agent)

| # | Method | Bug | Test that catches it |
|---|--------|-----|---------------------|
| 1 | `calculateDiscountCents()` | Threshold `> 10` should be `>= 10` — exactly 10-item orders receive no bulk discount | `testExactlyTenItemsQualifyForBulkDiscount` |
| 2 | `calculateSubtotalCents()` | Accumulator is `int` — overflows for orders > ~$21M | `testSubtotalDoesNotOverflowForLargeOrder` |
| 3 | `validatePaymentCard()` | Always returns `true` — no validation performed | `testInvalidPaymentCardIsRejected` |

## Scoring

| Criterion | Points |
|-----------|--------|
| Discount threshold >= 10 (Bug 1) | 25 |
| Subtotal uses long (Bug 2) | 30 |
| validatePaymentCard() validates (Bug 3) | 25 |
| All 5 tests pass | 10 |
| Test file unmodified | 5 |
| VLM bonus | 5 |
| **Total** | **100** |

**Pass threshold:** ≥ 70 points AND all 5 tests pass
