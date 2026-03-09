# Film Budget Variance Analysis

**Environment**: microsoft_excel_env
**Difficulty**: Very Hard
**Occupation**: Producers and Directors (SOC 27-2012)
**Industry**: Arts, Entertainment, and Media / Film Production

## Task Overview

The agent receives a production accounting workbook (`film_budget.xlsx`) for an independent feature film (~$1.8M budget) with 32 line items sourced from real published union rate schedules and BLS wage data. The agent must complete budget-vs-actual analysis by category, department-level summaries with overrun identification, and a contingency utilization tracker.

## Domain Context

Production accounting is a critical function on every film set. The production accountant tracks actual spending against the approved budget, identifies cost overruns by department, and monitors the contingency reserve. The AICP (Association of Independent Commercial Producers) standard form structures budgets into Above-the-Line (ATL: creative talent), Below-the-Line Production (BTL-Prod: crew and equipment), Post-Production, and Other (insurance, legal, contingency).

## Data Sources

**Line Item Detail** (Sheet 1, 32 rows, pre-filled):
Every line item uses exact published rates:

- **WGA**: Schedule of Minimums 2023, Low Budget Original Screenplay: $80,550
- **DGA**: Basic Agreement 2023 — Director prep $21,507/wk, shoot $24,115/wk; UPM $6,808/wk; 1st AD $5,848/wk
- **SAG-AFTRA**: TV/Theatrical Agreement 2023 — Low Budget weekly $7,472; day rate $2,151
- **IATSE Local 600** (Camera): DP $3,744/wk; Camera Op $3,151/wk; 1st AC $2,698/wk
- **IATSE Local 728** (Electric): Gaffer $52.62/hr
- **IATSE Local 80** (Grip): Key Grip $48.38/hr
- **IATSE Local 695** (Sound): Mixer $57.79/hr
- **IATSE Local 44** (Props): Journeyman $46.51/hr
- **BLS OEWS May 2023, California**: SOC 27-2012 ($101,130), 27-1011 ($114,380), 27-4032 ($94,920)
- **Equipment**: ARRI Alexa Mini LF package ~$4,500/day (Panavision 2023)
- **FilmLA**: Permit Fee Schedule 2023, baseline $805/day

Budget totals: ATL $754K, BTL-Prod $689K, Post $129K, Other $209K (incl. $140K contingency)

## Required Analysis

### Budget_vs_Actual sheet
For each of 4 categories: Total Budget, Total Actual, Variance ($), Variance (%), Committed, Paid, Remaining Committed, EAC, ETC, Status_Flag (OVER_BUDGET/ON_TRACK/UNDER_BUDGET at 5% threshold). GRAND TOTAL row.

### Department_Summary sheet
For each of ~20 departments: Budget Total, Actual Total, Variance, Line Item Count, Largest Overrun Item and Amount.

### Contingency_Tracker sheet
Original Budget (excl. contingency), Contingency Budget ($140K), Total Budget, Total Actual, Overrun amount, Contingency Used/Remaining, Utilization %, Projected Final Cost, Budget Health flag.

## Scoring (100 points)

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Total Budget for all 4 categories | 20 | Values in [$50K, $1M] |
| Grand Total Actual in [$1.55M, $1.85M] | 25 | Expected ~$1.70M |
| >= 2 distinct Status Flags present | 15 | OVER_BUDGET, ON_TRACK, UNDER_BUDGET |
| Contingency Utilization % in [30%, 100%] | 20 | Expected ~45% |
| >= 12 departments with Budget > 0 | 20 | 20 departments in data |

**Pass threshold**: 60 points
**Do-nothing score**: 0 (all output cells blank)

## Why This Is Hard

- SUMIF/SUMIFS across 32 line items by Category and Department
- Variance percentage calculations with division by budget amounts
- INDEX/MATCH with MAX to find largest overrun per department
- Contingency tracker requires multi-step calculation chain
- 20 departments x 5+ metrics each
- Status flag logic requires conditional evaluation of variance percentages
