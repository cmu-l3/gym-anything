# Loan Portfolio Amortization Model

## Occupation
Treasurers and Controllers

## Industry
Finance and Insurance

## Difficulty
very_hard

## Description
Corporate treasury management of a 6-loan commercial real estate portfolio with diverse structures (fixed-rate, variable-rate, balloon, interest-only). Agent must build individual amortization schedules using PMT/IPMT/PPMT, handle variable rates from a SOFR curve, create portfolio-level summaries, calculate DSCR covenant compliance, and perform interest rate sensitivity analysis.

## Data Source
Commercial real estate loan portfolio data based on real Federal Reserve H.15 selected interest rates (SOFR) and typical CRE loan structures from FDIC call report data.

## Features Exercised
- Financial formulas (PMT, IPMT, PPMT) for amortization
- Variable rate lookups from Rate_Curve sheet (INDEX-MATCH by date)
- Balloon payment and interest-only loan calculations
- DSCR covenant compliance (NOI / Debt Service)
- Sensitivity/scenario analysis (rate +/- 100bps)
- Conditional formatting for covenant compliance status

## Verification Criteria (6 criteria, 100 points)
1. Individual amortization schedules (min 4 of 6 loans) (20 pts)
2. Financial formulas PMT/IPMT/PPMT used correctly (20 pts)
3. Variable rate, balloon, and IO loan handling (15 pts)
4. Portfolio_Summary with balance and weighted avg rate (15 pts)
5. Covenant_Compliance with DSCR calculations (15 pts)
6. Sensitivity analysis and conditional formatting (15 pts)

## Do-Nothing Score
0 - Starter workbook has only 3 data sheets; verifier checks for 9 new sheets with financial formulas.
