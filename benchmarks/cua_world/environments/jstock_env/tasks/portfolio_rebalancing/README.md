# Task: portfolio_rebalancing

## Difficulty
Hard

## Domain Context

**Occupation**: Personal Financial Advisor (O*NET 13-2052.00)
**Industry**: Personal Financial Planning / Wealth Management

Personal financial advisors manage client investment portfolios and execute rebalancing transactions when portfolio allocations drift from target weights. This task reflects a common workflow: after a period of strong sector performance, the advisor must sell overweight positions and add to underweight ones to restore the Investment Policy Statement (IPS) target allocations, then export the sell record for compliance documentation.

## Task Overview

The agent must manage a client equity portfolio in JStock that has drifted into tech-sector overconcentration. It must execute four specific portfolio transactions (2 sells, 2 buys) using February 15, 2024 real market prices, and export the sell portfolio as a CSV file to the Desktop.

## Goal (End State)

At task completion, the "My Portfolio" portfolio in JStock must contain:
- A sell entry for 45 shares of AAPL at $184.15, dated Feb 15, 2024, broker $6.95
- A sell entry for 12 shares of NVDA at $674.72, dated Feb 15, 2024, broker $6.95
- A new buy entry for 35 shares of JNJ at $159.54, dated Feb 15, 2024
- A new buy entry for 55 shares of XOM at $103.87, dated Feb 15, 2024
- The sell portfolio must be exported as `/home/ga/Desktop/rebalance_sells_feb2024.csv`

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| SELL AAPL: 45 shares @ $184.15, Feb 15 2024, broker $6.95 | 20 | ±0.5 units, ±$0.15 price |
| SELL NVDA: 12 shares @ $674.72, Feb 15 2024, broker $6.95 | 20 | ±0.5 units, ±$0.15 price |
| BUY JNJ: 35 shares @ $159.54, Feb 15 2024 (new lot) | 20 | ±0.5 units, ±$0.15 price |
| BUY XOM: 55 shares @ $103.87, Feb 15 2024 (new lot) | 20 | ±0.5 units, ±$0.15 price |
| Export CSV file created at `/home/ga/Desktop/rebalance_sells_feb2024.csv` | 20 | file exists, mtime > task start |

**Pass threshold**: 60/100

## Verification Strategy

1. `export_result.sh` kills JStock to flush CSV data to disk
2. Reads `sellportfolio.csv` and `buyportfolio.csv` from `/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/`
3. Parses CSV with Python, extracts sell and buy entries by stock code
4. Checks for exported file on Desktop and its modification time
5. Writes all findings to `/tmp/portfolio_rebalancing_result.json`
6. `verifier.py` loads JSON, applies wrong-target gate (score=0 if no sells AND no new buys), then scores each criterion

## Data Sources

- Yahoo Finance historical closing prices:
  - Jan 2, 2024: AAPL $185.64, MSFT $374.51, NVDA $495.22, JNJ $152.10, XOM $99.64
  - Feb 15, 2024: AAPL $184.15, NVDA $674.72, JNJ $159.54, XOM $103.87

## Starting State

- Portfolio "My Portfolio" pre-populated with 5 holdings (AAPL/MSFT/NVDA/JNJ/XOM) at Jan 2 2024 prices
- Sell portfolio and dividend/deposit summaries are empty
- No Desktop export files exist

## Edge Cases

- Agent may try to sell shares that don't exist in the buy portfolio — JStock may allow this; verifier checks values regardless
- Sell portfolio CSV has different column order than buy portfolio — verifier handles both
- Export filename must match exactly (case-sensitive): `rebalance_sells_feb2024.csv`
- JNJ and XOM already exist in portfolio; verifier checks for new lots (by date Feb 15 2024) not just presence
