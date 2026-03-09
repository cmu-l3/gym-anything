# Task: VAR Analysis & Granger Causality — US Macroeconomic Dynamics

## Overview

This task requires an AI agent to conduct a full Vector Autoregression (VAR) analysis studying dynamic interactions between inflation and the interest rate using US quarterly macroeconomic data. This is a standard workflow for central bank economists, monetary policy researchers, and macroeconomic forecasters.

## Professional Context

Economists at central banks (Federal Reserve, ECB, Bank of England), research departments of investment banks, and academic macroeconomists routinely use VAR models to:
- Quantify how much of current inflation is explained by past interest rate movements
- Estimate whether the central bank's interest rate policy "Granger-causes" inflation outcomes
- Generate impulse response functions (IRFs) to simulate the effect of monetary shocks
- Perform variance decomposition to attribute forecast error variance

This is standard empirical monetary economics: every monetary policy analysis uses VAR/Granger causality.

## Dataset

- **File**: `usa.gdt` (from POE5 package, `/opt/gretl_data/poe5/usa.gdt`)
- **Source**: Hill, Griffiths, Lim — *Principles of Econometrics* 5th edition, US quarterly time-series
- **Observations**: 103 quarterly observations
- **Key variables**:
  - `inf`: quarterly inflation rate
  - `i`: nominal interest rate
  - `lc`: log real personal consumption
  - `ly`: log real disposable income

## Task Requirements

1. **Lag selection**: Use VAR lag order criteria (AIC, BIC/SBC, HQC) to determine optimal lag length p for a VAR of inf and i
2. **VAR estimation**: Estimate the VAR(p) model
3. **Granger causality tests**: Test both directions (inf→i and i→inf)
4. **Impulse response functions**: Generate IRFs for the shock transmission between inf and i
5. **Save results**: All output to `/home/ga/Documents/gretl_output/var_macro_results.txt`

## Goal State

The output file must contain:
- Lag selection criteria output
- VAR coefficient estimates
- Granger causality test statistics and p-values
- Impulse response function results or description

## Verification Strategy

1. **File exists and is new** (15 pts): created after task start
2. **VAR/lag selection evidence** (20 pts): keywords for information criteria (AIC, BIC, HQC, lag order)
3. **Granger causality test** (25 pts): keywords "Granger", "causality", "Wald" with p-value
4. **Impulse response functions** (25 pts): keywords "impulse", "IRF", "response", "orthogonalized"
5. **File substantiality** (15 pts): >4KB indicates comprehensive multi-step output

Pass threshold: 60/100

## Schema Reference

Gretl menus:
- VAR: Model > Time Series > Vector Autoregression (VAR)...
- Lag selection: From VAR dialog or model > Lag selection tab
- Granger causality: After VAR estimation, from model menu Tests > Granger causality
- IRF: After VAR estimation, Analysis > Impulse responses

## Notes

- The time series must be active (Gretl automatically handles this with .gdt files)
- Start with examining the VAR lag selection criteria carefully before estimating
- Granger causality in both directions constitutes a key deliverable
