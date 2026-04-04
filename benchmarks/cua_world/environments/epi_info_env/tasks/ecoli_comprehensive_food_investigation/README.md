# Task: ecoli_comprehensive_food_investigation

## Overview

An epidemiologist needs to conduct a comprehensive food outbreak investigation analysis on E. coli O157:H7 case-control data. Unlike the simple existing `run_frequency_analysis` task which just runs `FREQ ILLDUM`, this task requires a full analytical workflow: attack rate tables for all food items, multivariable logistic regression to identify independent risk factors, and epidemic curve analysis — the full suite of analyses that would appear in a field investigation report.

## Professional Context

**Primary occupation**: Epidemiologist / Field Epidemiologist / Preventive Medicine Physician

This task models the **real outbreak investigation workflow** used by CDC EIS officers and state epidemiologists:
1. Attack rate tables for each exposure (TABLES food_item ILLDUM)
2. Identify significant risk factors (p < 0.05)
3. Multivariable logistic regression to control for confounding
4. Epidemic curve analysis
5. Report generation

## Goal (End State)

Two output files containing a complete outbreak investigation analysis:

1. **`C:\Users\Docker\ecoli_food_investigation.html`** — Full analysis via ROUTEOUT including:
   - Frequency distributions of all food exposures and outcome
   - Attack rate table for EACH food item (TABLES analysis)
   - Multivariable logistic regression identifying independent risk factors
   - Onset date / epidemic curve analysis

2. **`C:\Users\Docker\ecoli_risk_factors.csv`** — Summary risk factor table via WRITE

## Dataset

- **Location**: `C:\EpiInfo7\Projects\EColi\EColi.mdb`
- **Table**: `FoodHistory`
- **Source**: Real CDC E. coli O157:H7 outbreak investigation data bundled with Epi Info 7
- **Records**: 359 individuals interviewed

Known variables (agent should confirm with FREQ *):
- `ILLDUM` — illness indicator (1=ill, 0=not ill)
- `HAMBURGER`, `HOTDOG`, `WATERMELON`, `LETTUCE`, `MUSTARD`, `RELISH`, `KETCHUP`, `ONION`, `PEPPERS`, `CORN`, `TOMATO`, `GROUNDMEAT` — food exposure variables
- `AGE`, `SEX` — demographic variables
- `ONSETDATE` — date of illness onset

## Analysis Required

### Phase 1: Data Exploration
```
READ {C:\EpiInfo7\Projects\EColi\EColi.mdb}:FoodHistory
ROUTEOUT "C:\Users\Docker\ecoli_food_investigation.html" REPLACE
FREQ *
```

### Phase 2: Attack Rate Tables (for each food item)
```
TABLES HAMBURGER ILLDUM
TABLES HOTDOG ILLDUM
TABLES WATERMELON ILLDUM
TABLES LETTUCE ILLDUM
[... repeat for all food variables ...]
```

### Phase 3: Multivariable Logistic Regression
```
LOGISTIC ILLDUM / HAMBURGER HOTDOG WATERMELON [significant_items...]
```

### Phase 4: Epidemic Curve
```
FREQ ONSETDATE
```

### Phase 5: Export
```
WRITE REPLACE "C:\Users\Docker\ecoli_risk_factors.csv" HAMBURGER HOTDOG WATERMELON ILLDUM
ROUTEOUT
```

## Verification Strategy

1. **HTML output exists and is newly created** (15 pts)
2. **HTML contains FREQ analysis with food variable content** (15 pts)
3. **HTML contains multiple TABLES analyses** (25 pts) — must have odds ratios for multiple food items
4. **HTML contains logistic regression output** (25 pts)
5. **CSV output exists and is newly created** (10 pts)
6. **HTML file is large** (10 pts) — size > 20 KB (comprehensive analysis = large file)

Pass threshold: 60/100 points

## Why This Is Harder Than Existing Tasks

The existing `run_frequency_analysis` task just runs `FREQ ILLDUM` — one command on one variable. This task requires:
- Running TABLES for each of 12+ food items (12+ separate commands)
- Interpreting statistical output to identify significant exposures
- Running multivariable LOGISTIC with the right variables
- Generating an epidemic curve
- Saving everything to files

This is a full outbreak investigation, not a single-command exercise.
