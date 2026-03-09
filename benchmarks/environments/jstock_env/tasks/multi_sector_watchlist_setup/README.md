# Task: multi_sector_watchlist_setup

## Difficulty
Hard

## Domain Context

**Occupation**: Securities Sales Agent (O*NET 41-3031.00)
**Industry**: Investment Banking / Institutional Brokerage

Securities sales agents at institutional brokerages maintain sector-specific coverage lists that correspond to their client's approved investment universe. This task reflects the common workflow of a sell-side analyst setting up coverage watchlists for a new institutional mandate, with precise alert thresholds for automated compliance notifications when positions approach review levels.

## Task Overview

The agent must create three new sector watchlists in JStock — `Technology_Coverage`, `Healthcare_Coverage`, and `Energy_Coverage` — each containing 3 specified stocks, each stock configured with exact Fall Below and Rise Above price alert values. Watchlist naming must be exact (referenced by automated compliance systems). Alert values must match the client-agreed thresholds precisely.

## Goal (End State)

At task completion, three new watchlists must exist in JStock:

**Technology_Coverage**: AAPL (170/200), GOOGL (125/155), MSFT (355/410)
**Healthcare_Coverage**: JNJ (145/175), UNH (495/565), PFE (22/32)
**Energy_Coverage**: XOM (95/120), CVX (140/168), COP (100/128)

Each stock must have both Fall Below and Rise Above alerts set to the specified values (±$2.00 tolerance).

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Technology_Coverage watchlist exists | 5 |
| Each of AAPL/GOOGL/MSFT in Technology_Coverage | 4 pts each (12 total) |
| Each Fall Below / Rise Above alert correct (±$2) | 3 pts each × 6 alerts (18 total) |
| Healthcare_Coverage watchlist exists | 5 |
| Each of JNJ/UNH/PFE in Healthcare_Coverage | 4 pts each (12 total) |
| Each alert correct × 6 | 3 pts each (18 total) |
| Energy_Coverage watchlist exists | 5 |
| Each of XOM/CVX/COP in Energy_Coverage | 4 pts each (12 total) |
| Each alert correct × 6 | 3 pts each (18 total) |

**Maximum**: 105 pts (capped at 100)
**Pass threshold**: 60/100

## Verification Strategy

1. `export_result.sh` kills JStock, then reads the three watchlist CSV files from `/home/ga/.jstock/1.0.7/UnitedState/watchlist/{ListName}/realtimestock.csv`
2. Parses each CSV, extracts Code, "Fall Below", and "Rise Above" columns
3. Stores per-stock entries in JSON at `/tmp/multi_sector_watchlist_setup_result.json`
4. `verifier.py` loads JSON, applies wrong-target gate (score=0 if no new watchlists), scores stock presence and alert values

## Data Sources

- Alert thresholds represent client-agreed ±10-15% rebalancing boundaries around approximate Jan 2024 market prices
- Reference prices (Jan 2024): AAPL ~$185, GOOGL ~$140, MSFT ~$375, JNJ ~$158, UNH ~$530, PFE ~$27, XOM ~$105, CVX ~$153, COP ~$113

## JStock Watchlist File Format

```
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","Apple Inc.","0.0",...,"170.0","200.0"
```

Path: `/home/ga/.jstock/1.0.7/UnitedState/watchlist/{WatchlistName}/realtimestock.csv`

## Starting State

- Only "My Watchlist" exists (containing SPY, AGG as placeholders)
- Technology_Coverage, Healthcare_Coverage, and Energy_Coverage directories removed by setup
- "My Portfolio" exists as baseline (agent must NOT modify it)

## Edge Cases

- Watchlist names are case-sensitive and underscore-separated — spaces or different cases will cause GATE failure
- JStock may show "0.0" for Fall Below/Rise Above if alert is not set — verifier checks that value > 0 and within tolerance
- Agent must use exact ticker symbols (GOOGL not GOOG; UNH not UNH.HK)
