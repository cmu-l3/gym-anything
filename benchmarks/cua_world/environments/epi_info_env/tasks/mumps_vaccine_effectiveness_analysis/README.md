# Task: mumps_vaccine_effectiveness_analysis

## Overview

An epidemiologist needs to evaluate vaccine effectiveness (VE) during a mumps outbreak investigation using Epi Info 7's Classic Analysis module. The Mumps dataset bundled with Epi Info 7 contains individual-level surveillance data from a real mumps outbreak, including vaccination history, illness status, demographics, and exposure information.

This is a realistic task that epidemiologists perform when evaluating whether vaccination provides adequate protection during an outbreak — a critical activity for informing public health response.

## Professional Context

**Primary occupation**: Epidemiologist (O*NET importance: 90, GDP contribution: $120M)

Epidemiologists routinely use Epi Info 7 to:
- Analyze outbreak investigation datasets
- Compute vaccine effectiveness using case-control and cohort methods
- Run multivariable regression to control for confounding
- Produce reports summarizing findings for public health decision-makers

## Goal (End State)

The agent must produce two output files containing a complete vaccine effectiveness analysis:

1. **`C:\Users\Docker\mumps_analysis.html`** — Full Classic Analysis output saved via ROUTEOUT, containing:
   - Frequency distributions of all key variables
   - 2x2 contingency table of vaccination status vs. illness outcome
   - Logistic regression output with odds ratios and 95% confidence intervals

2. **`C:\Users\Docker\mumps_ve_summary.csv`** — Summary CSV written via WRITE, containing at minimum the variable names with their odds ratios so VE can be computed as VE = (1 - OR) × 100%.

## Dataset

- **Location**: `C:\EpiInfo7\Projects\Mumps\Mumps.mdb`
- **Table**: `Survey`
- **Source**: Real Epi Info 7 bundled example dataset from CDC mumps outbreak investigation

The dataset contains variables related to:
- Illness/case status
- Vaccination status (doses received)
- Age groups
- Other demographic and exposure variables

The agent must explore the dataset structure using FREQ or VARIABLES to identify the correct variable names before running analyses.

## Analysis Required

### Step 1: Data Loading
```
READ {C:\EpiInfo7\Projects\Mumps\Mumps.mdb}:Survey
```

### Step 2: Exploratory Analysis
```
ROUTEOUT "C:\Users\Docker\mumps_analysis.html" REPLACE
FREQ *
```
(or individual FREQ on each variable to understand the data)

### Step 3: Bivariate Analysis
```
TABLES [vaccination_variable] [illness_variable]
```

### Step 4: Multivariable Logistic Regression
```
LOGISTIC [illness_variable] / [vaccination_variable] [age_variable] [other_covariates]
```

### Step 5: Save Summary
```
WRITE REPLACE "C:\Users\Docker\mumps_ve_summary.csv" [variable] [or_field] [ci_field]
```

## Verification Strategy

The verifier checks:
1. **HTML output exists and is newly created** (15 pts) — file must exist and have mtime > task_start
2. **HTML contains frequency analysis** (20 pts) — file must contain "Frequency" keyword and row count data
3. **HTML contains 2x2 table analysis** (20 pts) — file must contain odds ratio or "TABLES" output keywords
4. **HTML contains logistic regression** (25 pts) — file must contain "Odds Ratio", "Confidence", or "Logistic" keywords with numeric values
5. **CSV output exists and is newly created** (10 pts) — file must exist and have mtime > task_start
6. **HTML file is substantial** (10 pts) — file size > 5 KB indicating meaningful output

Pass threshold: 60/100 points

## Setup State

The setup script:
- Kills any existing Epi Info processes
- Launches Classic Analysis (Analysis.exe)
- Dismisses license/update dialogs
- Loads the Mumps dataset and runs VARIABLES to show the agent available field names
- Leaves the analysis program editor ready for the agent to type commands

## Key Epi Info Commands

| Command | Purpose |
|---------|---------|
| `READ {path}:Table` | Open a dataset |
| `FREQ variable` | Frequency distribution |
| `FREQ *` | All variables |
| `TABLES exposure outcome` | 2x2 table with OR/RR |
| `LOGISTIC outcome / predictors` | Logistic regression |
| `ROUTEOUT "path.html" REPLACE` | Redirect output to file |
| `ROUTEOUT` | Stop redirecting (close file) |
| `WRITE REPLACE "path.csv" var1 var2` | Write data to CSV |

## Evidence

- Setup screenshot saved to evidence_docs/
- Do-nothing test: score=0, passed=False (HTML and CSV don't exist until agent creates them)
