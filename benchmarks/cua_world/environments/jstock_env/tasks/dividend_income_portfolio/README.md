# Task: dividend_income_portfolio

## Difficulty
Hard

## Domain Context

**Occupation**: Financial Manager (O*NET 11-3031.00)
**Industry**: Family Office / Private Wealth Management

Financial managers at family offices set up and maintain investment tracking for their clients' portfolios. This task reflects the setup phase of a new income strategy: creating a dedicated portfolio, recording initial purchases with compliance-required comment tags, and logging the first dividend payments received from each position.

## Task Overview

The agent must create a new JStock portfolio named "Income Portfolio", record 4 dividend-paying equity purchases with specific broker fees and required compliance keywords in comments, and then record 2 dividend income entries (AT&T Q1 quarterly and Realty Income monthly). All data must match Yahoo Finance closing prices for January 15, 2024.

## Goal (End State)

Portfolio "Income Portfolio" must exist and contain:
- 4 buy transactions (T, VZ, KO, O) dated Jan 15, 2024, each with broker fee $9.99 and specific comment keywords
- 2 dividend summary entries (T: $55.50 on Feb 1; O: $20.52 on Feb 15)

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Portfolio "Income Portfolio" created | 5 |
| BUY T: 200sh @ $17.11, Jan 15 2024, $9.99 broker, comment has 'high-yield telecom' | 20 |
| BUY VZ: 150sh @ $38.58, Jan 15 2024, $9.99 broker, comment has '5G income' | 20 |
| BUY KO: 100sh @ $58.02, Jan 15 2024, $9.99 broker, comment has 'dividend aristocrat' | 20 |
| BUY O: 80sh @ $53.10, Jan 15 2024, $9.99 broker, comment has 'monthly REIT' | 20 |
| DIV T: $55.50 on Feb 1, 2024 | 7 |
| DIV O: $20.52 on Feb 15, 2024 | 8 |

**Pass threshold**: 60/100

Each buy criterion sub-scored: units (4pts), price (4pts), date (4pts), broker (4pts), comment keyword (4pts)

## Verification Strategy

1. `export_result.sh` kills JStock, reads `buyportfolio.csv` and `dividendsummary.csv` from `/home/ga/.jstock/1.0.7/UnitedState/portfolios/Income Portfolio/`
2. Parses CSV files, finds last entry per stock code (for buy) and last entry per code (for dividend)
3. Writes findings to `/tmp/dividend_income_portfolio_result.json`
4. `verifier.py` checks portfolio existence, then gates on portfolio_exists or buy_count > 0

## Data Sources

- Yahoo Finance closing prices, January 15, 2024:
  - T (AT&T): $17.11
  - VZ (Verizon): $38.58
  - KO (Coca-Cola): $58.02
  - O (Realty Income): $53.10
- AT&T Q1 2024 dividend: $0.2775/share × 200 shares = $55.50 (paid Feb 1, 2024)
- Realty Income February 2024 monthly dividend: $0.2565/share × 80 shares = $20.52 (paid Feb 15, 2024)

## JStock Portfolio File Paths

- Buy portfolio: `/home/ga/.jstock/1.0.7/UnitedState/portfolios/Income Portfolio/buyportfolio.csv`
- Dividend summary: `/home/ga/.jstock/1.0.7/UnitedState/portfolios/Income Portfolio/dividendsummary.csv`

## Starting State

- "My Portfolio" exists with 1 BND holding (unrelated baseline data)
- "Income Portfolio" directory removed by setup
- Agent must create "Income Portfolio" as a new portfolio in JStock

## Edge Cases

- Comment keyword matching is case-insensitive substring check
- Portfolio name must be exactly "Income Portfolio" (space, not underscore)
- Dividend entries require navigating to the portfolio's dividend panel (different from buy transactions)
- AT&T ticker is "T" (single letter), which may require care in JStock's ticker search
