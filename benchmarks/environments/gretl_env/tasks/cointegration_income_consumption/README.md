# Task: Cointegration Analysis — Permanent Income Hypothesis (FRED Data)

## Overview

A macroeconomist tests the Permanent Income Hypothesis (PIH) by examining whether real consumption and real disposable income are cointegrated. If they share a common stochastic trend (cointegration), deviations from the long-run relationship are temporary — consistent with the PIH. This requires the Engle-Granger two-step cointegration procedure, preceded by ADF unit root tests on both series.

This is a paradigmatic empirical macroeconomics task performed at central banks, research institutions, and academic departments worldwide.

## Professional Context

Macroeconomists at the Federal Reserve, International Monetary Fund, Congressional Budget Office, and academic departments use cointegration analysis to:
- Test long-run economic equilibrium relationships (PIH, PPP, Fisher equation)
- Build Error Correction Models (ECMs) for short-run dynamics around long-run trends
- Distinguish spurious regression from genuine long-run relationships
- Inform forecasting models for consumption and income

The Engle-Granger test (Engle & Granger, 1987 — Nobel Prize 2003) is standard in any serious time-series econometrics analysis of macroeconomic data.

## Dataset

Real data from the Federal Reserve Bank of St. Louis (FRED) — no fabrication:
- **PCEC96.csv**: Real Personal Consumption Expenditures (billions chained 2017$, quarterly, FRED series PCEC96)
- **DSPIC96.csv**: Real Disposable Personal Income (billions chained 2017$, quarterly, FRED series DSPIC96)
- **Source**: US Bureau of Economic Analysis, distributed via FRED
- **Files placed at**: `/home/ga/Documents/gretl_data/`

## Task Requirements

1. **Import data**: Open both CSVs in Gretl and configure as quarterly time series
2. **Log-transform**: Generate `lcons = log(PCEC96)` and `linc = log(DSPIC96)`
3. **ADF unit root tests**: Test lcons and linc in levels (non-stationary expected) and first differences (stationary expected) — both should be I(1)
4. **Engle-Granger step 1**: Estimate cointegrating OLS: `lcons ~ linc`, save residuals
5. **Engle-Granger step 2**: Run ADF on residuals — reject H₀ of unit root = cointegration confirmed
6. **Interpretation**: State whether series are cointegrated
7. **Save**: All results to `/home/ga/Documents/gretl_output/cointegration_results.txt`

## Goal State

Output file must contain evidence of:
- ADF test results for levels (unit roots in lcons and linc)
- ADF test results for first differences (stationarity after differencing)
- Cointegrating regression (OLS of lcons on linc)
- ADF test on residuals (Engle-Granger test)

## Verification Strategy

1. **File exists and is new** (15 pts): created after task start
2. **ADF unit root tests in levels** (20 pts): keywords "ADF", "Dickey-Fuller", "unit root", "level"
3. **Cointegrating regression present** (20 pts): keyword for OLS with lcons/linc/consumption/income
4. **ADF on residuals (Engle-Granger)** (25 pts): keywords "residual", "cointegrat", "Engle", "Granger"
5. **First-difference stationarity** (10 pts): first difference ADF keyword
6. **File substantiality** (10 pts): >5KB for full test sequence

Pass threshold: 60/100

## Schema Reference

Gretl workflow:
- File > Open data > Import CSV
- Set date/time structure: Data > Dataset structure > Time series
- Generate variables: Add > Define new variable (e.g., `lcons = log(PCEC96)`)
- ADF test: Variable > Unit root tests > Augmented Dickey-Fuller
- OLS: Model > Ordinary Least Squares
- Save residuals: After OLS, Tests > Residuals > Save residuals
- ADF on residuals: Variable > Unit root tests > ADF

## Notes

- The FRED CSV format: first column = date, second column = value
- May need to handle missing values (NAs) from FRED for initial quarters
- The cointegration relationship is lcons regressed on linc (not the other way around, though both are valid)
- Quarterly data spanning 1947–present gives ~300+ observations — substantial power for cointegration tests
