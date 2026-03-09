# Task: CPS Log-Wage Regression Diagnostics

## Overview

A wage researcher must rigorously validate whether a Mincer log-wage equation is correctly specified. This requires running multiple diagnostic tests — RESET, Breusch-Pagan, White — and responding appropriately to findings. This is a standard applied econometrics workflow in labor economics, policy analysis, and survey data research.

## Professional Context

Labor economists and policy analysts at the Bureau of Labor Statistics, Congressional Budget Office, Federal Reserve Banks, and academic departments routinely estimate Mincer wage equations and must validate the OLS assumptions. Failing to test for heteroskedasticity in cross-sectional wage data (which is nearly universal) leads to invalid standard errors and incorrect inference. The RESET test catches functional form errors that invalidate the entire model.

Occupations that perform this workflow: Economists (BLS/CBO/Fed), survey research directors, policy analysts at think tanks (Urban Institute, Brookings), academic labor economists, HR analytics professionals.

## Dataset

- **File**: `cps5_small.gdt` (from POE5, `/opt/gretl_data/poe5/cps5_small.gdt`)
- **Source**: Current Population Survey (CPS) 2013 Outgoing Rotation Groups, sample extracted for POE5
- **Observations**: 1,200 workers
- **Key variables**:
  - `wage`: hourly earnings (need log transformation)
  - `educ`: years of education
  - `exper`: years of potential experience
  - `expersq`: experience squared
  - `female`: =1 if female
  - `black`: =1 if Black
  - `metro`: =1 if metropolitan area
  - `south`, `midwest`, `west`: regional dummies

## Task Requirements

1. **Log-wage OLS**: Generate `lwage = log(wage)` or use `l(wage)` in model; regress on educ, exper, expersq, female, black, metro, south
2. **RESET test**: Ramsey's specification test (Tests > RESET after running OLS)
3. **Breusch-Pagan test**: BP heteroskedasticity test (Tests > Heteroskedasticity > Breusch-Pagan)
4. **White test**: White's general heteroskedasticity test (Tests > Heteroskedasticity > White)
5. **Robust standard errors**: Re-estimate OLS with HC (heteroskedasticity-consistent) standard errors if heteroskedasticity detected
6. **Save**: All results to `/home/ga/Documents/gretl_output/wage_diagnostics.txt`

## Goal State

The output file must contain evidence of all four steps: OLS regression results, RESET test output, Breusch-Pagan test output, and White test output. Ideally also includes HC/robust SE estimation.

## Verification Strategy

1. **File exists and is new** (15 pts)
2. **OLS regression present** (15 pts)
3. **RESET test present** (20 pts)
4. **Breusch-Pagan test present** (20 pts)
5. **White test present** (20 pts)
6. **File substantiality** (10 pts): >4KB for 4 tests worth of output

Pass threshold: 60/100

## Schema Reference

Gretl menus:
- OLS: Model > Ordinary Least Squares
- Log transform: Add `genr lwage = log(wage)` or use `l(wage)` syntax
- RESET: After OLS, Tests > RESET...
- Breusch-Pagan: After OLS, Tests > Heteroskedasticity > Breusch-Pagan
- White test: After OLS, Tests > Heteroskedasticity > White's test
- Robust SE: In OLS dialog, check "Robust standard errors (HC)"

## Notes

- The log transformation is essential — do NOT regress wage (levels) if trying to use Mincer specification
- Both BP and White tests are required; they test different aspects of heteroskedasticity
- RESET with 2 auxiliary regressors is standard practice
