# Task: Panel Data FE vs RE — Hausman Specification Test (NLS Panel)

## Overview

A labor economist must select the appropriate panel data estimator for a wage equation. The choice between Fixed Effects (FE) and Random Effects (RE) has major implications for interpretation and efficiency. The Hausman test is the standard diagnostic for this decision. This workflow is performed routinely in empirical panel data research.

## Professional Context

Economists at the Federal Reserve, World Bank, academic departments, and policy institutes use panel data to control for unobserved individual heterogeneity. The Hausman test distinguishes whether individual effects are correlated with regressors (FE required) or uncorrelated (RE valid and more efficient). Labor economists analyzing wage dynamics, health economists studying treatment effects, and development economists studying microfinance all perform this workflow regularly.

The NLS panel data on young women's wages is one of the canonical datasets in labor economics — used in hundreds of published papers.

## Dataset

- **File**: `nls_panel.gdt` (from POE5, `/opt/gretl_data/poe5/nls_panel.gdt`)
- **Source**: National Longitudinal Survey (NLS) of Young Women, selected by Hill, Griffiths, Lim for POE5
- **Structure**: Panel data — 716 individuals × multiple time periods
- **Key variables**:
  - `lwage`: log hourly wage
  - `educ`: years of education
  - `exper`: years of work experience
  - `expersq`: experience squared
  - `black`: =1 if Black
  - `south`: =1 if southern region
  - `union`: =1 if union member
  - `tenure`: job tenure in years

## Task Requirements

1. **Pooled OLS**: lwage ~ educ + exper + expersq + black + south + union (ignores panel structure)
2. **Fixed Effects (FE)**: Within estimator — controls for time-invariant individual heterogeneity
3. **Random Effects (RE)**: GLS estimator — assumes individual effects are uncorrelated with regressors
4. **Hausman test**: Compare FE vs RE estimates; if significant, FE is consistent and RE is not
5. **Interpretation**: State which estimator is recommended based on Hausman test p-value
6. **Save**: All results to `/home/ga/Documents/gretl_output/panel_results.txt`

## Goal State

Output file must contain:
- Pooled OLS regression results
- Fixed Effects model results
- Random Effects model results
- Hausman specification test statistic and p-value

## Verification Strategy

1. **File exists and is new** (15 pts)
2. **Pooled OLS results** (15 pts)
3. **Fixed Effects results** (20 pts)
4. **Random Effects results** (20 pts)
5. **Hausman test present** (20 pts)
6. **File substantiality** (10 pts): >5KB for 4 model outputs

Pass threshold: 60/100

## Schema Reference

Gretl menus for panel models:
- The dataset must be configured as panel first (should already be in nls_panel.gdt)
- Pooled OLS: Model > Ordinary Least Squares (panel dataset will show OLS option)
- Fixed Effects: Model > Panel > Fixed effects
- Random Effects: Model > Panel > Random effects (EGLS)
- Hausman test: After Random Effects model, Tests > Hausman test

## Notes

- Panel structure is pre-configured in the .gdt file (unit and time variables set)
- Education ('educ') is time-invariant for most women — this means FE cannot identify its coefficient
- Note whether the FE model drops time-invariant regressors — this is expected behavior
- The Hausman test chi-squared statistic and p-value are the key deliverables
