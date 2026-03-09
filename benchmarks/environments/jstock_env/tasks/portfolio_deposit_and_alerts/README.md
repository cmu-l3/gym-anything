# Task: portfolio_deposit_and_alerts

## Difficulty
Hard

## Domain Context

**Occupation**: Investment Fund Manager (O*NET 11-3031.03)
**Industry**: Hedge Fund / Multi-Asset Management

Investment fund managers at newly-launched funds must initialize their tracking infrastructure: recording the initial capital allocation, purchasing the first positions, and setting macro-level monitoring alerts for all instruments in the investment universe. This task reflects fund inception day operations.

## Task Overview

The agent must create a new JStock portfolio "Fund Alpha", record a $500,000 inception deposit, record two initial equity purchases (SPY and BRK.B) at January 2, 2024 closing prices, then create a "Fund Alpha Watch" watchlist with precisely calibrated macro monitoring alerts for 6 instruments.

## Goal (End State)

Portfolio "Fund Alpha" must contain:
- Deposit: $500,000.00 on Jan 2, 2024, comment containing "inception"
- BUY SPY: 300sh @ $470.46, Jan 2 2024, broker $0.00, comment "core beta allocation"
- BUY BRK.B: 200sh @ $363.21, Jan 2 2024, broker $0.00, comment "value equity allocation"

Watchlist "Fund Alpha Watch" must contain all 6 instruments with alerts:
- SPY: Fall Below $445.00, Rise Above $510.00
- QQQ: Fall Below $385.00, Rise Above $440.00
- BRK.B: Fall Below $338.00, Rise Above $395.00
- GLD: Fall Below $178.00, Rise Above $210.00
- TLT: Fall Below $89.00, Rise Above $108.00
- VTI: Fall Below $225.00, Rise Above $260.00

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Portfolio "Fund Alpha" created | 3 |
| Deposit $500K on Jan 2 2024, comment "inception" | 17 |
| BUY SPY: 300sh @ $470.46, Jan 2, $0 broker, "core" comment | 14 |
| BUY BRK.B: 200sh @ $363.21, Jan 2, $0 broker, "value" comment | 14 |
| SPY alerts (Fall Below $445 / Rise Above $510) | 8 |
| QQQ alerts (Fall Below $385 / Rise Above $440) | 8 |
| BRK.B alerts (Fall Below $338 / Rise Above $395) | 8 |
| GLD alerts (Fall Below $178 / Rise Above $210) | 8 |
| TLT alerts (Fall Below $89 / Rise Above $108) | 8 |
| VTI alerts (Fall Below $225 / Rise Above $260) | 8 |

**Maximum**: ~96 pts (capped at 100)
**Pass threshold**: 60/100 (deposit + buys or buys + most alerts)

## Verification Strategy

1. `export_result.sh` kills JStock, reads `depositsummary.csv` and `buyportfolio.csv` from "Fund Alpha" portfolio
2. Reads `Fund Alpha Watch/realtimestock.csv` watchlist
3. Finds deposit entry, last SPY/BRK.B buy entries, and per-stock alert values
4. Writes to `/tmp/portfolio_deposit_and_alerts_result.json`
5. `verifier.py` gates on portfolio not existing + no data, then scores each component

## Data Sources

Yahoo Finance closing prices, January 2, 2024:
- SPY: $470.46 (S&P 500 ETF)
- BRK.B: $363.21 (Berkshire Hathaway Class B)
- QQQ: ~$408 (reference only, not purchased)
- GLD: ~$192 (reference only)
- TLT: ~$96 (reference only)
- VTI: ~$240 (reference only)

Alert levels represent tactical rebalancing triggers (approximately ±5-10% from Jan 2, 2024 prices).

## JStock File Paths

- Deposit: `/home/ga/.jstock/1.0.7/UnitedState/portfolios/Fund Alpha/depositsummary.csv`
- Buy: `/home/ga/.jstock/1.0.7/UnitedState/portfolios/Fund Alpha/buyportfolio.csv`
- Watchlist: `/home/ga/.jstock/1.0.7/UnitedState/watchlist/Fund Alpha Watch/realtimestock.csv`

## Starting State

- "My Portfolio" exists with AAPL baseline (unrelated)
- "My Watchlist" with AAPL alert (pre-existing, must not interfere)
- "Fund Alpha" portfolio removed by setup
- "Fund Alpha Watch" watchlist removed by setup

## Edge Cases

- Deposit amount: $500,000 (half a million) — agent must enter correct number of zeros
- BRK.B ticker: must be entered as "BRK.B" (with dot); JStock may require exact symbol
- Broker fee of $0.00 for ETF purchases — many brokers offer commission-free ETF trading
- Deposit functionality is in JStock's Portfolio panel (separate from buy/sell transactions)
- Watchlist "Fund Alpha Watch" name contains a space before "Watch"
