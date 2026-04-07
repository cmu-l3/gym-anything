# Pacific Northwest Timber Cruise Volume Analysis (`timber_cruise_volume@1`)

## Overview

This task evaluates the agent's ability to implement forestry-specific volume estimation formulas, variable-radius plot expansion calculations, and stand-level summary statistics in Excel. The agent must compute per-tree board-foot volumes using species-specific combined variable equations, expand to per-acre estimates using basal area factor prism sampling, summarize volumes and stumpage values by species, and calculate stand-level metrics for a 40-acre Coast Range timber sale appraisal.

## Rationale

**Why this task is valuable:**
- Tests domain-specific formula implementation (forestry volume equations with species-dependent coefficients)
- Requires multi-sheet coordination with SUMPRODUCT, SUMIF, and nested IF lookups
- Evaluates understanding of sampling expansion factors (variable-radius plot sampling)
- Exercises conditional logic for harvest eligibility determination
- Real-world professional forestry workflow with economic significance

**Real-world Context:** A forester with the Oregon Department of Forestry has completed a variable-radius point sampling timber cruise of a 40-acre second-growth Douglas-fir/mixed conifer stand in the Oregon Coast Range (Tillamook State Forest). The field data—80 trees across 10 sample points—has been entered into Excel. Before presenting the timber sale appraisal to the District Forester, per-tree volumes must be calculated, expanded to per-acre estimates, and summarized by species with current stumpage values. The appraisal determines whether the stand meets the minimum 25 MBF/acre threshold for an economically viable harvest unit.

## Task Description

**Goal:** Calculate per-tree timber volumes and expand to stand-level estimates for a 40-acre tract.

**Starting State:** Excel is open with `timber_cruise.xlsx`.
- **Sheet `Tree_Data`**: Raw field data (Species, DBH, Height, Defect) for 80 trees.
- **Sheet `Coefficients`**: Regression coefficients (b0, b1) and stumpage prices by species.
- **Sheet `Volume_Calculations`**: Tree data is pre-copied here. Columns H-N are blank.
- **Sheet `Stand_Summary`**: Summary table shell is waiting for calculations.

**Expected Actions:**
1. **Per-Tree Calculations (`Volume_Calculations` sheet):**
   - **Basal Area:** `0.005454 * DBH^2`
   - **TPA (Trees Per Acre):** `BAF / Basal Area` (BAF=20)
   - **Gross BF Volume:** `b0 + b1 * DBH^2 * Merch_Height` (Lookup coeffs by Species)
   - **Net BF Volume:** `Gross * (1 - Defect%)`
   - **Vol Per Acre:** `Net Volume * TPA`
   - **Stumpage $ Per Acre:** `(Vol Per Acre / 1000) * Price` (Lookup price by Species)
   - **Size Class:** "Large" (>=24"), "Medium" (>=16"), "Small" (<16")

2. **Stand Summary (`Stand_Summary` sheet):**
   - **Species Summaries:** Calculate MBF/Acre and $/Acre for each species.
     *Formula:* `(Sum of Vol_Per_Acre for Species) / (Number of Plots * 1000)`
     *(Note: Since TPA expands to "Trees Per Acre represented by this tree", summing Vol_Per_Acre for all trees across all plots and dividing by N plots gives the stand average.)*
   - **Stand Totals:** Scale per-acre averages by 40 acres.
   - **Metrics:** Calculate QMD and determine Harvest Eligibility (>25 MBF/ac and QMD >14").

**Final State:** All calculations complete and file saved.

## Verification Strategy

### Primary Verification: Cell Value Checks
The verifier extracts data from the saved Excel file and compares it against a ground-truth calculation performed in Python using the same raw data and coefficients.

### Secondary Verification: Formula Structure
The verifier checks that formulas are used (e.g., cell J2 starts with `=`) rather than hardcoded values, preventing manual calculation outside of Excel.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Tree Vol Calcs (Gross/Net) | 25 | Correct implementation of volume equation & defect |
| Expansion (BA/TPA) | 15 | Correct Basal Area and expansion factor formulas |
| Economic Calcs ($/Acre) | 15 | Correct price lookup and unit conversion |
| Classification (Size Class) | 5 | Correct IF logic |
| Stand Summary (Per Species) | 20 | Correct aggregation logic (Sum / N_Plots) |
| Stand Totals (Vol/Val) | 10 | Correct multiplication by stand acres |
| Key Metrics (QMD/Eligible) | 10 | Correct QMD formula and Eligibility logic |
| **Total** | **100** | |

Pass Threshold: 60 points