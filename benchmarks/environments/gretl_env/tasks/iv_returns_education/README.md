# Task: IV Returns to Education (Mroz 1987)

## Overview

This task tests an AI agent's ability to conduct instrumental variables (IV/2SLS) estimation in Gretl — a workflow that econometricians, labor economists, and policy researchers perform routinely when analyzing wage determinants with endogenous regressors.

The dataset is the classic **Mroz (1987)** sample of 753 married women from the 1975 Panel Study of Income Dynamics (PSID). The core challenge: education is endogenous in a wage equation because unobserved ability simultaneously raises both wages and educational attainment. Parents' education (fatheduc, motheduc) serve as valid instruments — they affect the child's education but have no direct effect on wages beyond that channel.

## Professional Context

Applied economists at central banks, think tanks, universities, and government agencies routinely use IV/2SLS to address endogeneity in observational data. The Mincer wage equation with IV correction is a textbook example taught in every graduate econometrics course. Real practitioners (labor economists, education policy analysts, development economists) use exactly this workflow: OLS baseline → IV estimation → Hausman test → interpretation.

## Dataset

- **File**: `mroz.gdt` (from POE5 package, `/opt/gretl_data/poe5/mroz.gdt`)
- **Source**: Mroz, T.A. (1987). "The Sensitivity of an Empirical Model of Married Women's Hours of Work to Economic and Statistical Assumptions." *Econometrica*, 55(4):765–799.
- **Observations**: 753 married women; 428 are employed (inlf==1, wage>0)
- **Key variables**:
  - `lwage`: log hourly wage (only observed for employed women)
  - `educ`: years of education
  - `exper`: years of work experience
  - `expersq`: experience squared
  - `fatheduc`: father's years of education (instrument)
  - `motheduc`: mother's years of education (instrument)
  - `inlf`: =1 if in the labor force

## Task Requirements

The agent must:

1. **OLS baseline**: Estimate `lwage ~ educ + exper + expersq` restricted to employed women (inlf==1 or drop observations with missing lwage)
2. **2SLS/IV estimation**: Re-estimate using fatheduc and motheduc as instruments for educ
3. **Hausman test**: Test whether OLS estimates are inconsistent (endogeneity test)
4. **Save output**: All results saved to `/home/ga/Documents/gretl_output/iv_wage_results.txt`

## Goal State

The output file `/home/ga/Documents/gretl_output/iv_wage_results.txt` must exist and contain evidence of:
- OLS regression results (coefficient on educ, standard errors)
- 2SLS/IV regression results (coefficient on educ using parental education instruments)
- Hausman endogeneity test statistics

## Verification Strategy

The verifier checks:
1. **File exists and is new** (created after task start): 15 points
2. **OLS results present** (keywords: "OLS", "Ordinary Least Squares", R-squared, or F-statistic): 20 points
3. **IV/2SLS results present** (keywords: "2SLS", "TSLS", "instrumental", "IV estimation", or "Two-Stage"): 25 points
4. **Hausman test present** (keywords: "Hausman", "endogeneity", "Wu-Hausman"): 25 points
5. **File substantiality** (>3KB indicates multiple estimation outputs, not just one model): 15 points

Pass threshold: 60/100

## Schema Reference

Key Gretl menus for this task:
- OLS: Model > Ordinary Least Squares
- IV/2SLS: Model > Instrumental Variables > Two Stage Least Squares
- Hausman test: run after 2SLS, from model window Tests menu, or via script

## Edge Cases

- The lwage variable has missing values for non-employed women — Gretl will automatically drop them in regression
- Father's/mother's education = 0 is valid (no formal education) — do not treat as missing
- The agent must save the text output — a screenshot or window view alone does not count
