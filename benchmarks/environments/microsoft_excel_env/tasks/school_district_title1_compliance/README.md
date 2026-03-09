# School District Title I Compliance Analysis

**Environment**: microsoft_excel_env
**Difficulty**: Very Hard
**Occupation**: Education Administrators, All Other (SOC 11-9032)
**Industry**: K-12 Education / School District Administration

## Task Overview

The agent receives a school district workbook (`school_district.xlsx`) for Botetourt County Public Schools (Virginia) and must perform a complete Title I compliance analysis across four sheets: computing per-pupil expenditures, conducting a federal comparability analysis between Title I and non-Title I schools, and allocating $582,174 in Title I funds using weighted formulas with supplement-not-supplant verification.

## Domain Context

Title I of the Every Student Succeeds Act (ESSA) provides federal funding to schools with high concentrations of students from low-income families. School districts must demonstrate "comparability" (ESSA Section 1118(c)) — that Title I schools receive substantially comparable resources to non-Title I schools — and must ensure Title I funds supplement, not supplant, state and local funding. The allocation methodology uses poverty-weighted formulas based on Free/Reduced Lunch (FRL) percentages.

## Data Sources

**School-Level Data** (School_Data sheet, pre-filled):
- Source: NCES Common Core of Data (CCD) 2022-23, Botetourt County VA (LEAID 5100420)
- Retrieved via Urban Institute Education Data API
- 11 active schools: 7 Elementary, 2 Middle, 2 High
- Real enrollment, FRL counts, and teacher FTEs from NCES CCD

**Salary Data**:
- Source: BLS OEWS May 2023, Virginia
- Elementary Teachers (SOC 25-2021): $61,770 median
- Middle School Teachers (SOC 25-2022): $63,280 median
- Secondary Teachers (SOC 25-2031): $64,190 median
- Education Administrators, K-12 (SOC 11-9032): $95,770 median
- Teacher Assistants (SOC 25-9041): $29,850 median
- Office Clerks (SOC 43-9061): $37,220 median

**Benefits Rate**: 35.3% (VRS employer contribution FY2024 22.61% + FICA 7.65% + health ~5%)

**State Average PPE**: $14,603 (NCES Digest 2023 Table 236.65, Virginia 2021-22)

**Title I Allocation**: $582,174 (Virginia DOE Title I Allocations FY2023, Botetourt County)

## Required Analysis

### Expenditure_Analysis sheet
For each school: Personnel Cost, Benefits Cost (Personnel x 35.3%), Total Compensation, Supplies/Technology/Facilities costs, Total Expenditure, Per-Pupil Expenditure, comparison to state average, flag (BELOW_STATE_AVG / ABOVE_STATE_AVG). Fill DISTRICT TOTAL row.

### Comparability_Report sheet
PPE excluding Title I, FTE per 100 students, adjusted teacher salary. Comparability test: compute Title I vs non-Title I averages, ratios (must be >= 0.90 per ESSA), and overall status.

### Title_I_Allocation sheet
Allocation weights by FRL tier (>= 75%: 1.40, >= 50%: 1.20, < 50%: 1.00), weighted FRL counts, proportional allocation of $582,174, per-pupil Title I, supplement-not-supplant check.

## Scoring (100 points)

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Per-Pupil Expenditure for >= 9 of 11 schools | 20 | PPE values in $4,000-$15,000 range |
| District Total Expenditure in [$30M, $45M] | 25 | Correct summation |
| Comparability Status present (COMPARABLE/NON-COMPARABLE) | 15 | Status determination completed |
| Title I Allocation Total ~ $582,174 | 20 | Within [$550K, $620K] |
| Supplement Check values (>= 3 PASS/FAIL) | 20 | 4 Title I eligible schools checked |

**Pass threshold**: 60 points
**Do-nothing score**: 0 (all output cells blank)

## Why This Is Hard

- Agent must navigate 4 interconnected sheets with cross-references
- Expenditure calculations require combining FTEs x salaries across 3 staff categories
- Comparability test requires conditional averages (AVERAGEIF) for Title I vs non-Title I
- Title I allocation uses weighted proportional formulas with tier-based weights
- Supplement check requires comparing each school's PPE to the non-Title I average
- 11 schools x 20+ calculations each = substantial formula work
