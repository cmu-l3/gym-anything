# Task: salmonella_foodnet_surveillance_analysis

## Overview

A foodborne disease epidemiologist needs to analyze CDC FoodNet Salmonella surveillance data to prepare an annual surveillance summary report. The dataset is drawn from CDC's FoodNet Active Surveillance Network — the gold standard for foodborne illness monitoring in the U.S. — and includes real case counts, serotype data, and incidence rates by state.

## Professional Context

**Primary occupation**: Epidemiologist / Clinical Data Manager / Preventive Medicine Physician

State epidemiologists routinely:
- Receive annual surveillance datasets from CDC FoodNet
- Analyze trends over time by serotype (Typhimurium, Enteritidis, Newport, etc.)
- Compare incidence rates across surveillance sites/states
- Stratify by age group and sex to identify high-risk populations
- Produce annual reports summarizing surveillance findings

This task requires using SELECT for temporal filtering, MEANS for incidence rate comparison across states, and stratified TABLES analyses — a much richer workflow than single-variable FREQ commands.

## Goal (End State)

Two output files representing a complete surveillance analysis:

1. **`C:\Users\Docker\salmonella_surveillance_report.html`** — Full analysis via ROUTEOUT including:
   - Frequency distributions of Serotype, State, AgeGroup, Sex
   - MEANS analysis of IncidenceRate by State
   - TABLES analyses for Serotype × State or other cross-tabulations
   - Temporal trend analysis using SELECT Year>=2015

2. **`C:\Users\Docker\salmonella_serotype_summary.csv`** — Summary data exported via WRITE

## Dataset

- **Location**: `C:\Users\Docker\salmonella_surveillance.mdb`
- **Table**: `SalmonellaCases`
- **Source**: Based on real CDC FoodNet Annual Summary data (https://www.cdc.gov/foodnet/surveillance.html)
- **Columns**: Year, Serotype, State, CaseCount, IncidenceRate, AgeGroup, Sex
- **Year range**: 2010-2020
- **Setup**: Created by setup_task.ps1 using 32-bit PowerShell + Jet OLEDB 4.0 from CDC FoodNet summary statistics

## Analysis Required

### Phase 1: Load and Explore
```
READ {C:\Users\Docker\salmonella_surveillance.mdb}:SalmonellaCases
ROUTEOUT "C:\Users\Docker\salmonella_surveillance_report.html" REPLACE
FREQ *
```

### Phase 2: Key Distributions
```
FREQ Serotype
FREQ State
FREQ AgeGroup
FREQ Sex
```

### Phase 3: Incidence Rate Analysis
```
MEANS IncidenceRate State
MEANS IncidenceRate Serotype
```

### Phase 4: Cross-tabulation
```
TABLES Serotype State
TABLES AgeGroup Serotype
```

### Phase 5: Temporal Analysis
```
SELECT Year>=2015
FREQ Serotype
MEANS IncidenceRate State
SELECT
```

### Phase 6: Export
```
WRITE REPLACE "C:\Users\Docker\salmonella_serotype_summary.csv" Year Serotype State CaseCount IncidenceRate
ROUTEOUT
```

## Verification Strategy

1. **HTML output exists and is newly created** (15 pts)
2. **HTML contains frequency distributions with surveillance variables** (20 pts) — Serotype, State, AgeGroup keywords
3. **HTML contains MEANS/incidence rate analysis** (20 pts)
4. **HTML contains SELECT/temporal filtering evidence** (20 pts)
5. **CSV output exists and is newly created** (15 pts)
6. **HTML file is substantial** (10 pts) — size > 10 KB

Pass threshold: 60/100

## Setup Details

The setup script creates the salmonella_surveillance.mdb file using:
- 32-bit PowerShell and Jet OLEDB 4.0 provider
- Real Salmonella serotype data based on CDC FoodNet annual summaries
- Top serotypes: Typhimurium, Enteritidis, Newport, Javiana, Heidelberg, Montevideo, Muenchen, Oranienburg
- 10 FoodNet surveillance sites/states: CA, CO, CT, GA, MD, MN, NM, NY, OR, TN
- Age groups: <5, 5-17, 18-49, 50-64, 65+
- Years 2010-2020 with realistic incidence rates and case counts
