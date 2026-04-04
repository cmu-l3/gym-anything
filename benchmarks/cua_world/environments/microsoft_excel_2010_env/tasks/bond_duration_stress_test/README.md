# Bond Duration Stress Test

**Environment**: microsoft_excel_2010_env
**Difficulty**: Very Hard
**Occupation**: Investment Fund Manager / Fixed Income Portfolio Manager (SOC 11-3031)
**Industry**: Investment Management / Asset Management

## Task Overview

The agent receives a 10-bond fixed-income portfolio workbook (`bond_portfolio.xlsx`) and must implement a complete duration risk analysis using Excel bond math formulas. The workbook has three sheets: a pre-filled `Portfolio` sheet with raw bond characteristics, a blank `Duration_Analysis` sheet where the agent must compute duration and risk metrics, and a blank `Shock_Scenario` sheet where the agent must estimate P&L impact of parallel yield curve shifts.

## Domain Context

Modified Duration is the primary interest rate sensitivity metric used by fixed income portfolio managers. It measures the percentage change in a bond's price for a 1% change in yield. Dollar Value of a Basis Point (DV01) measures the dollar change for a 1bp (0.01%) yield move. Convexity adjusts duration for the non-linear price-yield relationship. Portfolio stress testing with ±100bps and ±50bps shocks is standard practice for regulatory and internal risk reporting.

## Data Sources

**US Treasury Yield Curve** (settlement date: January 15, 2024):
- Source: US Department of the Treasury, Daily Treasury Par Yield Curve Rates
- URL: https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?type=daily_treasury_yield_curve&field_tdr_date_value_month=202401
- Jan 15, 2024 par yields: 1-yr ~5.00%, 2-yr ~4.37%, 5-yr ~4.04%, 7-yr ~4.11%, 10-yr ~4.05%, 20-yr ~4.36%, 30-yr ~4.27%
- FRED series IDs: DGS2, DGS5, DGS10, DGS30 (Federal Reserve Bank of St. Louis)
- Treasury bonds in portfolio (Bonds 1, 3, 4) have YTMs calibrated to these published par yields

**Corporate Bond Spreads** (investment-grade, Jan 2024):
- Source: ICE BofA US Corporate Master OAS (FRED series BAMLC0A0CM): ~93 bps over Treasuries for A/BBB-rated corporates on Jan 15, 2024
- BBB-rated 10-yr corporate spread ~125–140 bps over Treasuries in Jan 2024
- URL: https://fred.stlouisfed.org/series/BAMLC0A0CM

**Municipal Bond Yields** (tax-exempt, Jan 2024):
- Source: MSRB/EMMA Market Statistics; Bloomberg BVAL Municipal Benchmark
- AAA municipal 10-yr yield ~3.0–3.2% as of Jan 2024 (approximately 75% of Treasury yield, reflecting federal tax exemption)
- Reference: SIFMA Municipal Bond Market Statistics Q4 2023

**Portfolio Construction**:
- 10-bond portfolio spanning 2-year to 30-year maturities represents a typical institutional core-plus fixed income mandate
- Par values ($500K–$1M per bond) represent standard institutional round-lot sizes
- Settlement date: January 15, 2024 (standard T+1 settlement for US fixed income secondary market)

## Data

**Portfolio sheet** (pre-filled, read-only inputs):

| Bond | Type | Coupon | Maturity | Par ($) | Price (% of par) | YTM | Periods/Year |
|------|------|--------|----------|---------|------------------|-----|--------------|
| 1–10 | Mixed Treasuries/Corporates/Munis | 2.5%–6.5% | 1–30yr | 500K–1M | ~95–104% | 2.1%–5.8% | 1–2 |

## Required Analysis

### Duration_Analysis sheet (agent fills in)

For each bond, compute:
- **Macaulay Duration**: `SUM(t × PV(CF_t)) / Bond Price` — period-weighted average of discounted cash flow times, divided by bond price
- **Modified Duration**: `Macaulay Duration / (1 + YTM/periods_per_year)`
- **Market Value ($)**: `Par × (Price/100)`
- **DV01 ($)**: `Market Value × Modified Duration / 10,000`
- **Convexity**: Period-weighted PV of cash flows divided by bond price, adjusted for periods
- **Flag**: "DURATION_BREACH" if Modified Duration > 7.0 years

Expected Modified Durations (approximate):
- Bond 1: 1.90 yr (2-yr Treasury), Bond 2: 4.49 yr, Bond 3: 8.18 yr (10-yr Treasury)
- Bond 4: 16.08 yr (30-yr Treasury), Bond 5: 5.78 yr, Bond 6: 8.64 yr
- Bond 7: 11.29 yr (20-yr Corporate), Bond 8: 4.58 yr, Bond 9: 6.58 yr, Bond 10: 10.44 yr

Breach bonds (ModDur > 7.0): Bonds 3, 4, 6, 7, 10 (5 bonds)

Portfolio weighted-average Modified Duration: ~6.88 years
Total portfolio DV01: ~$2,967

### Shock_Scenario sheet (agent fills in)

For each bond:
- **+100bps P&L**: `Market Value × (−Modified Duration × 0.01 + 0.5 × Convexity × 0.01²)`
- **−100bps P&L**: same formula with +0.01 shift
- **+50bps P&L**: same with 0.005 shift

Expected total portfolio P&L for +100bps: approximately −$290,000 to −$300,000

## Scoring (100 points)

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Modified Duration values present for ≥7 bonds (range 1.0–20.0) | 20 | ≥7 bonds populated |
| At least 3 ModDur values within ±8% of ground truth | 25 | Correct formula used |
| DURATION_BREACH flags for ≥3 of 5 expected breach bonds | 15 | Correct 7.0yr threshold |
| Portfolio weighted-average ModDur in [6.0, 7.8] | 20 | Correct MV-weighting |
| Shock_Scenario +100bps total P&L in [−$360K, −$230K] | 20 | Duration-based P&L formula |

**Pass threshold**: 60 points
**Do-nothing score**: 0 (all output cells blank in starter file)

## Why This Is Hard

- Macaulay Duration requires building and summing a per-period cash flow schedule in Excel
- Modified Duration builds on Macaulay Duration via a division by (1 + YTM/freq)
- DV01 requires combining market value and Modified Duration
- Portfolio weighted-average requires SUMPRODUCT across MV-weighted duration
- Shock P&L formula uses both duration AND convexity (non-linear adjustment)
- Bonds have different coupon frequencies (semi-annual vs annual) — must handle both
- 10 bonds × ~30 periods each = substantial formula work
- Agent must recognize the Duration_Analysis → Shock_Scenario dependency chain

## Verification Strategy

1. **is_new check**: Export script records modification time; verifier rejects stale (unmodified) files
2. **Independent xlsx re-analysis**: Verifier independently copies xlsx (not relying solely on export JSON) and parses with openpyxl `data_only=True` to read cached formula results
3. **Range validation**: All ModDur values checked to be in plausible range [1.0, 20.0]
4. **Accuracy check**: Ground-truth ModDur values used for ±8% tolerance check
5. **Flag check**: DURATION_BREACH string matching in flag column
