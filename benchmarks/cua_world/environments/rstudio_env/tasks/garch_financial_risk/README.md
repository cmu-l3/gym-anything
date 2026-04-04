# Task: GARCH Volatility Modeling and VaR Estimation for S&P 500

## Domain Context

**Occupation**: Financial Quantitative Analyst
**GDP impact**: ~$415M (Financial Quantitative Analysts using RStudio, ONET importance=92)

Quantitative analysts at banks, hedge funds, and risk management firms routinely build GARCH-family volatility models for Value-at-Risk (VaR) computation — a core regulatory requirement under Basel III. The S&P 500 SPY ETF is the most widely traded financial instrument, and daily VaR estimation using GARCH(1,1) is a standard industry workflow.

## Dataset

**Source**: Real SPY (SPDR S&P 500 ETF Trust) daily price data downloaded from Yahoo Finance
**Period**: 2015-01-01 to 2023-12-31 (~2260 trading days)
**URL at setup time**: Downloaded via getSymbols("SPY", from="2015-01-01")

**Columns**: Date, Open, High, Low, Close, Volume, Adjusted

## Analysis Pipeline

### Model: GARCH(1,1)
The GARCH(1,1) model specifies:
- σ²_t = ω + α₁ε²_{t-1} + β₁σ²_{t-1}
- r_t = μ + ε_t, where ε_t = σ_t·z_t, z_t ~ N(0,1)

### Deliverables

1. **spy_var_estimates.csv**: Daily log-returns, conditional volatility (σ_t), and VaR at 95%/99%
   - VaR_95 = μ_hat + σ_t * qnorm(0.05) (should be negative, e.g., -0.012)
   - VaR_99 = μ_hat + σ_t * qnorm(0.01) (more negative, e.g., -0.018)

2. **spy_backtest.csv**: Kupiec Proportion of Failures (POF) test results
   - Tests if actual exceedance rates match theoretical rates

3. **spy_garch_report.png**: 3-panel visualization

## Verification Strategy

1. VaR CSV exists, is new, has correct columns, and has >200 rows
2. VaR_99 values are more negative than VaR_95 (correct ordering)
3. Conditional volatility is in realistic annualized range (5%–150%)
4. Backtest CSV exists with Kupiec test statistics
5. Plot PNG exists, is new, >50KB
6. R script contains rugarch function calls

## Why This Task Is Hard

1. **Package discovery**: Must find and install `rugarch` from CRAN (not pre-installed)
2. **API complexity**: `rugarch` has a complex specification API (`ugarchspec`, `ugarchfit`, `ugarchforecast`)
3. **Financial conventions**: Must know that VaR is expressed as a negative number (loss), not a positive one
4. **Multiple deliverables**: VaR CSV + Backtest CSV + 3-panel plot
5. **Kupiec test**: Requires implementing the LR test statistic manually or finding the right function
6. **Visualization**: Overlaying VaR bands on returns with highlighted exceedances requires multi-layer ggplot2

## Expected Results (ground truth for verification)

- Conditional volatility (annualized) during COVID crash (March 2020): ~100-150%
- Normal periods: ~10-20%
- VaR_95 exceedance rate: should be close to 5%
- VaR_99 exceedance rate: should be close to 1%
- GARCH alpha + beta coefficients sum: should be < 1 (stationarity condition)
