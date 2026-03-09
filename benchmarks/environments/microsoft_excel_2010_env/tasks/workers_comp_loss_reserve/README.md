# Workers Compensation Loss Reserve Analysis

**Environment**: microsoft_excel_2010_env
**Difficulty**: Very Hard
**Occupation**: Actuary / P&C Loss Reserve Analyst (SOC 15-2011)
**Industry**: Property & Casualty Insurance

## Task Overview

The agent receives a workers' compensation cumulative paid loss triangle workbook (`workers_comp_triangle.xlsx`) in NAIC Schedule P format covering accident years 2019–2023 across five development periods (12, 24, 36, 48, 60 months). The workbook has three sheets: a pre-filled `Triangle`, and two blank analysis sheets (`LDF_Development`, `IBNR_Reserve`). The agent must implement the full chain-ladder reserving method: compute age-to-age LDFs, volume-weighted average LDFs, CDF-to-Ultimate factors, and IBNR reserves, then flag under-reserved accident years.

## Domain Context

The chain-ladder (development) method is the industry-standard actuarial technique for projecting ultimate losses in P&C insurance. NAIC Schedule P filings require all US P&C insurers to disclose loss development data annually. Reserve adequacy is a key concern for state regulators — accident years where IBNR exceeds 20% of ultimate indicate the company may be under-reserved, which can impair solvency. Actuaries use volume-weighted LDFs rather than simple averages because they give proportionally more weight to accident years with higher loss volumes.

## Data Sources

**Cumulative Paid Loss Triangle**:
- Source: Representative workers compensation program constructed using NAIC Schedule P industry aggregate development patterns
- Reference: NAIC Property/Casualty Industry — Schedule P, Workers Compensation (Exhibit 2, Loss Development)
- NAIC Annual Statistical Bulletin 2023: https://content.naic.org/sites/default/files/statistical-studies-annual-statistical-bulletin.htm
- NAIC publishes industry-aggregate WC LDFs annually; for the 2022 Statistical Bulletin, WC VW LDFs were approximately 12→24: 1.40–1.45, 24→36: 1.13–1.21, 36→48: 1.07–1.10, 48→60: 1.04–1.06
- The triangle values represent a mid-size regional employer WC program with development factors consistent with those published NAIC industry ranges
- Tail factor of 1.025 at 60 months is at the conservative end of NAIC WC tail factors (range 1.01–1.05 per NAIC Exhibit 3)

**Accident Year Range**: 2019–2023 (5-year development window, representing a program that began reporting under modern WC reforms)

## Data

**Triangle sheet** (pre-filled, $000s):

| AY | 12M | 24M | 36M | 48M | 60M |
|----|-----|-----|-----|-----|-----|
| 2019 | 31,420 | 44,850 | 52,380 | 56,840 | 59,650 |
| 2020 | 33,880 | 48,180 | 56,320 | 61,110 | — |
| 2021 | 36,240 | 51,320 | 60,050 | — | — |
| 2022 | 39,680 | 56,490 | — | — | — |
| 2023 | 41,340 | — | — | — | — |

Tail factor (60M to ultimate): **1.025** (given in LDF_Development!B12)

## Required Analysis

### LDF_Development sheet (agent fills in)

**Individual LDFs** (rows 4–8, columns B–E):
- For each AY and each adjacent period pair where both exist: `later period / earlier period`

**Volume-Weighted Average LDFs** (row 10):
- `SUM(all later-period values) / SUM(all earlier-period values)` across eligible AYs

Expected VW LDFs:
- 12→24: **1.4222** (sum: 200,840 / 141,220)
- 24→36: **1.1690** (sum: 168,750 / 144,350)
- 36→48: **1.0851** (sum: 117,950 / 108,700)
- 48→60: **1.0494** (sum: 59,650 / 56,840)

**CDF-to-Ultimate** (rows 16–20, column H):
- AY 2019 (at 60M): Tail only = 1.0250
- AY 2020 (at 48M): VW_48_60 × Tail = 1.0494 × 1.025 = 1.0757
- AY 2021 (at 36M): VW_36_48 × VW_48_60 × Tail = 1.1672
- AY 2022 (at 24M): VW_24_36 × … = 1.3645
- AY 2023 (at 12M): all 4 VW LDFs × Tail = **1.9406**

### IBNR_Reserve sheet (agent fills in)

For each AY (rows 4–8):
- **CDF-to-Ultimate**: pulled from LDF_Development sheet
- **Projected Ultimate**: Current Paid × CDF
- **IBNR Reserve**: Projected Ultimate − Current Paid
- **IBNR % of Ultimate**: IBNR / Projected Ultimate × 100
- **Adequacy Flag**: "UNDER_RESERVED" if IBNR% > 20%

Expected results:
- AY 2019: IBNR=$1,491K (2.4%), no flag
- AY 2020: IBNR=$4,624K (7.0%), no flag
- AY 2021: IBNR=$10,041K (14.3%), no flag
- AY 2022: IBNR=$20,591K (26.7%) → **UNDER_RESERVED**
- AY 2023: IBNR=$38,883K (48.5%) → **UNDER_RESERVED**
- **Total IBNR**: ~$75,631K ($75.6M)

## Scoring (100 points)

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| VW LDF 12→24 in [1.40, 1.45] | 25 | Correct volume-weighting |
| VW LDF 24→36 in [1.13, 1.21] | 20 | Correct formula |
| Total IBNR within ±15% of $75,631K | 25 | Correct CDF chain applied |
| At least 2 UNDER_RESERVED flags | 20 | Correct 20% threshold |
| AY 2023 CDF-to-Ultimate in [1.85, 2.05] | 10 | Correct full-chain product |

**Pass threshold**: 60 points
**Do-nothing score**: 0 (all output cells blank in starter file)

## Why This Is Hard

- Volume-weighted LDF formula (`SUM(numerator) / SUM(denominator)`) is non-obvious; simple average is wrong
- CDF-to-Ultimate is a product chain that must include the correct subset of remaining LDFs for each AY
- Cross-sheet formula references between LDF_Development and IBNR_Reserve required
- UNDER_RESERVED flag requires IBNR % calculation before comparison — two-step derivation
- 5 AYs × 4 LDF columns + 5 CDF rows + 5 IBNR rows = substantial formula work
- Correct identification of the "diagonal" (most recent value) for each AY is required

## Verification Strategy

1. **is_new check**: Export script records file modification time; verifier gates on is_new
2. **Independent xlsx re-analysis**: Verifier copies xlsx and parses with openpyxl `data_only=True`
3. **VW LDF check**: Row 10 of LDF_Development checked for values in correct ranges
4. **IBNR total check**: Sum of IBNR column checked against expected total ±15%
5. **Flag count**: UNDER_RESERVED string count in IBNR_Reserve adequacy flag column
6. **AY 2023 CDF**: Specific CDF value for least-mature AY validated
