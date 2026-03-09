# Task: hiv_transmission_route_analysis

## Overview

A public health epidemiologist needs to analyze HIV case surveillance data to characterize transmission routes and demographic risk factors. This task represents a core public health workflow: descriptive analysis of surveillance data to identify which populations and transmission categories account for the highest disease burden, and stratified analysis to examine whether patterns differ by demographic subgroup.

## Professional Context

**Primary occupation**: Epidemiologist / Community Health Worker / Preventive Medicine Physician

Real epidemiologists routinely:
- Analyze surveillance case reports to understand disease patterns
- Stratify analyses by demographic group (sex, race/ethnicity, age)
- Use SELECT statements to filter to specific subpopulations
- Produce HTML reports for program managers and policymakers
- Export tabular data for further processing in other tools

## Goal (End State)

Two output files representing a complete HIV transmission route analysis:

1. **`C:\Users\Docker\hiv_transmission_analysis.html`** — Full analysis output via ROUTEOUT, containing:
   - Frequency distributions of all key variables (transmission category, sex, age group, race/ethnicity)
   - MEANS analysis on any continuous variables
   - TABLES analyses showing relationships between transmission category and other variables
   - At least one stratified analysis using SELECT

2. **`C:\Users\Docker\hiv_transmission_summary.csv`** — Summary data exported via WRITE

## Dataset

- **Location**: `C:\EpiInfo7\Projects\HIV\HIV.mdb`
- **Table**: `Case`
- **Source**: Real Epi Info 7 bundled HIV surveillance dataset from CDC

The dataset contains variables related to HIV cases including transmission category, demographics, and clinical indicators. The agent must discover exact variable names using FREQ or VARIABLES commands.

## Analysis Required

### Step 1: Data Loading and Exploration
```
READ {C:\EpiInfo7\Projects\HIV\HIV.mdb}:Case
ROUTEOUT "C:\Users\Docker\hiv_transmission_analysis.html" REPLACE
FREQ *
```

### Step 2: Bivariate Analyses
```
TABLES [transmission_var] [outcome_var]
MEANS [continuous_var] [grouping_var]
```

### Step 3: Stratified Analysis
```
SELECT [sex_var]="Male"
TABLES [transmission_var] [outcome_var]
SELECT
SELECT [sex_var]="Female"
TABLES [transmission_var] [outcome_var]
SELECT
```

### Step 4: Export Summary
```
WRITE REPLACE "C:\Users\Docker\hiv_transmission_summary.csv" [relevant_vars]
ROUTEOUT
```

## Verification Strategy

1. **HTML output exists and is newly created** (15 pts)
2. **HTML contains FREQ/descriptive analysis content** (20 pts) — transmission, demographic keywords
3. **HTML contains TABLES or cross-tabulation analysis** (20 pts)
4. **HTML contains stratified analysis** (20 pts) — SELECT command evidence, subgroup analysis
5. **CSV output exists and is newly created** (15 pts)
6. **HTML file is substantial** (10 pts) — size > 5 KB

Pass threshold: 60/100 points

## Key Commands

| Command | Usage |
|---------|-------|
| `SELECT condition` | Filter records |
| `SELECT` | Remove filter (reset to all records) |
| `MEANS var` | Mean, SD, min, max |
| `MEANS var groupvar` | Means by group |
| `FREQ var` | Frequency table |
| `TABLES exposure outcome` | Cross-tabulation with statistics |
| `ROUTEOUT "path" REPLACE` | Redirect output to file |
| `WRITE REPLACE "path" vars` | Export data rows to CSV |
