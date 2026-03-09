# Task: tax_lot_portfolio_tracking

## Difficulty
Hard

## Domain Context

**Occupation**: Accountant / CPA (O*NET 13-2011.00)
**Industry**: Public Accounting / Tax Preparation

CPAs preparing annual tax returns for clients with significant brokerage accounts must track individual tax lots separately for FIFO cost basis calculations. This task reflects the setup of a new tax-year tracking portfolio with multiple purchase lots across different dates and prices, a FIFO disposition sale, and watchlist alerts for remaining open positions.

## Task Overview

The agent must create a new portfolio "Tax Lots 2024" containing 5 buy entries (2 COST lots, 2 META lots, 1 AMZN lot) with clearing fees, 1 COST sell entry for FIFO lot disposition, and a new watchlist "Tax Watch 2024" with 52-week range alerts for META and AMZN.

## Goal (End State)

Portfolio "Tax Lots 2024" must contain:
- COST lot 1: 10sh @ $638.22, Dec 1 2023, broker $4.95, clearing $0.20, comment "COST lot 1 Dec 2023"
- COST lot 2: 8sh @ $715.40, Jan 19 2024, broker $4.95, clearing $0.20, comment "COST lot 2 Jan 2024"
- META lot 1: 20sh @ $367.15, Dec 15 2023, broker $4.95, clearing $0.20, comment "META lot 1 Dec 2023"
- META lot 2: 12sh @ $484.10, Jan 26 2024, broker $4.95, clearing $0.20, comment "META lot 2 Jan 2024"
- AMZN: 30sh @ $172.35, Feb 2 2024, broker $4.95, clearing $0.20
- COST sell: 10sh @ $755.60, Feb 22 2024, broker $4.95

Watchlist "Tax Watch 2024" must contain:
- META: Fall Below $350.00, Rise Above $525.00
- AMZN: Fall Below $155.00, Rise Above $195.00

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Portfolio "Tax Lots 2024" created | 3 |
| COST lot 1: units/price/date/broker/clearing/comment | 15 |
| COST lot 2: units/price/date/broker/clearing/comment | 15 |
| META lot 1: units/price/date/broker/clearing/comment | 15 |
| META lot 2: units/price/date/broker/clearing/comment | 15 |
| AMZN: units/price/date/broker/clearing | 14 |
| COST sell: units/price/date/broker | 12 |
| META watchlist alerts (Fall Below + Rise Above) | 6 |
| AMZN watchlist alerts (Fall Below + Rise Above) | 4 |

**Pass threshold**: 60/100 (approximately: 3 or more complete buy lots)

## Verification Strategy

1. `export_result.sh` kills JStock, reads `buyportfolio.csv` and `sellportfolio.csv` from "Tax Lots 2024" portfolio
2. Reads `Tax Watch 2024/realtimestock.csv` watchlist
3. Groups buy entries by stock code (multiple lots per code expected)
4. Writes to `/tmp/tax_lot_portfolio_tracking_result.json`
5. `verifier.py` matches lots by code + lot number ordering (first entry for lot 1, second for lot 2)

## Data Sources

Yahoo Finance historical closing prices:
- COST: Dec 1, 2023 — $638.22; Jan 19, 2024 — $715.40; Feb 22, 2024 — $755.60
- META: Dec 15, 2023 — $367.15; Jan 26, 2024 — $484.10
- AMZN: Feb 2, 2024 — $172.35

Alert values represent approximate 52-week trading ranges:
- META: 52-week low ~$260 adjusted; ~$350 as support; ~$525 as resistance
- AMZN: ~$155 as support; ~$195 as resistance

## JStock Portfolio File Paths

- Buy: `/home/ga/.jstock/1.0.7/UnitedState/portfolios/Tax Lots 2024/buyportfolio.csv`
- Sell: `/home/ga/.jstock/1.0.7/UnitedState/portfolios/Tax Lots 2024/sellportfolio.csv`
- Watchlist: `/home/ga/.jstock/1.0.7/UnitedState/watchlist/Tax Watch 2024/realtimestock.csv`

## Starting State

- "My Portfolio" exists with SPY baseline holding (unrelated)
- "Tax Lots 2024" portfolio removed by setup
- "Tax Watch 2024" watchlist removed by setup

## Edge Cases

- Clearing fee field is separate from broker fee — both must be filled correctly
- Multiple lots for the same code appear as multiple rows in buyportfolio.csv; verifier matches by insertion order
- META ticker must be entered as "META" (not "FB" or other variants)
- COST sell entry goes into sellportfolio.csv, not buyportfolio.csv
