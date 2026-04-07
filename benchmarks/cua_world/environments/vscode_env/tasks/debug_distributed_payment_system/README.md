# Debug Distributed Payment System

**Occupation**: Software Developer (15-1252.00)
**Industry**: Fintech
**Difficulty**: very_hard

## Description

A fintech company's payment processing system has 5 critical bugs causing financial discrepancies. Customers have reported failed transactions, incorrect currency conversions, and duplicate charges. The agent must find and fix all bugs with no hints about what is wrong.

## Bugs Injected (5 total, 20 points each)

1. **Float arithmetic for money** (`payment_processor.py`) - Uses `float()` for monetary calculations, causing rounding errors. Fix: use `Decimal`.
2. **Inverted FX rate** (`currency_converter.py`) - Multiplies by rate instead of dividing for inverse currency pair lookups.
3. **Insufficient amount validation** (`transaction_validator.py`) - Missing `MAX_TRANSACTION_LIMIT` check and type validation.
4. **Reversed debit/credit for liabilities** (`ledger.py`) - Treats all account types as assets; liability accounts need inverted debit/credit logic.
5. **Case-sensitive idempotency keys** (`idempotency.py`) - Keys compared without case normalization, allowing duplicate transactions.

## Scoring

- Each fix: 20 points
- Pass threshold: 60 points (3 of 5 bugs fixed)
- Maximum: 100 points

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task configuration |
| `setup_task.sh` | Creates workspace with buggy code and test suite |
| `export_result.sh` | Exports modified source files for verification |
| `verifier.py` | Scores each bug fix independently |
| `README.md` | This file |
