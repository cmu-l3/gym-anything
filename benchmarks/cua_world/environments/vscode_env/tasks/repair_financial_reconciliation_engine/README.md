# Repair Financial Reconciliation Engine

## Scenario

A regional bank's automated reconciliation system for matching internal ledger
entries against bank statements has been producing incorrect results. Legitimate
transactions are flagged as exceptions, foreign currency transactions frequently
fail to match, and the exception report contains suspicious groupings where
debits and credits cancel each other out.

The agent must find and fix all 5 critical bugs in the reconciliation engine
before the month-end close deadline.

## Occupation

**Financial and Investment Analyst** (SOC 13-2051.00) -- Banking Industry

## Skills Tested

- Financial computing and decimal precision
- Foreign exchange (FX) spread mechanics
- Timezone-aware date handling
- Transaction matching and tolerance logic
- Exception reporting and sign awareness
- Python debugging in a domain-specific context

## Workspace

`/home/ga/workspace/reconciliation_engine/`

| File | Purpose |
|------|---------|
| `config.py` | Engine configuration (FX rates, tolerances, timezones) |
| `engine/matcher.py` | Transaction matching engine |
| `engine/fx_handler.py` | Foreign exchange conversion with spread |
| `engine/date_handler.py` | Date normalization and business day logic |
| `engine/tolerance_checker.py` | Amount tolerance checking |
| `engine/exception_reporter.py` | Exception report generation |
| `run_reconciliation.py` | Main pipeline entry point |

## Difficulty

**Very Hard** -- requires domain-specific financial knowledge including decimal
precision pitfalls, FX bid/ask spreads, timezone handling near midnight, tolerance
calculation methodology, and sign-aware transaction grouping.

## Verification

The verifier checks whether each of the 5 bugs has been correctly fixed.
Scoring: 20 points per bug fix (pass threshold: 60/100).
