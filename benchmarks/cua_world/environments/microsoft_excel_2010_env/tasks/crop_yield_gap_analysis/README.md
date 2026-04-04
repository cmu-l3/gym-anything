# Iowa Corn Yield Gap Analysis

**Environment**: microsoft_excel_2010_env
**Difficulty**: Very Hard
**Occupation**: Agricultural and Food Scientists / Farm Managers (SOC 19-1011, 11-9013)
**Industry**: Agriculture / State Extension Services

## Task Overview

The agent receives an Iowa county-level corn yield analysis workbook (`iowa_corn_yield.xlsx`) with 22 Iowa counties. The `County_Data` sheet contains real 2022 actual corn yields from USDA NASS, ISU Extension district attainable yield benchmarks as potential yields, and 2022 harvested acreage. The `Yield_Gap_Analysis` sheet has actual yields, potential yields, and harvested areas pre-filled; all derived metric columns are blank. The agent must implement agricultural yield gap statistics using IF, RANK, and SUMPRODUCT functions across 22 counties.

## Domain Context

Yield gap analysis quantifies the difference between a crop's actual yield and its attainable potential yield given current technology and inputs. USDA NASS and Iowa State University Extension publish county-level corn yield data for benchmarking. Agricultural economists use yield gap metrics to prioritize extension program resources — counties with high yield gaps receive targeted agronomic consulting. Area-weighted averages account for larger counties' greater contribution to state totals.

## Data Sources

**Actual 2022 County Yields**:
- Source: USDA National Agricultural Statistics Service, Iowa Ag News — 2022 Corn County Estimates
- Published: February 24, 2023
- URL: https://www.nass.usda.gov/Statistics_by_State/Iowa/Publications/County_Estimates/2023/IA-CtyEst-Corn-02-23.pdf
- Iowa state average: 200.0 bu/acre
- 22 counties selected spanning Northeast, North Central, East Central, Central, and Southwest Iowa

**Potential Yield Benchmarks**:
- Source: Iowa State University Extension district attainable yield benchmarks and NRCS soil productivity data
- Northeast district: 250 bu/acre (dark Tama-Muscatine silt loam soils, high organic matter)
- North Central district: 235 bu/acre (Webster-Harps clay loam, Des Moines lobe till plain)
- East Central district: 246 bu/acre (Downs-Tama silt loam, adequate drainage)
- Central district: 242 bu/acre (Nicollet-Webster complex, productive karst terrain)
- Southwest district (county-specific): Pottawattamie 240 (Missouri River valley, NRCS Class I-II), Cass 215 (rolling loess hills, NRCS Class II-III), Adair 200 (Adair Hills steep loess, NRCS Class III)

**2022 Context**: Iowa's 2022 growing season saw drought impacts concentrated in western Iowa (U.S. Drought Monitor), reducing SW Iowa yields substantially below their potential. Pottawattamie County's 195.0 bu/acre was down from 216.3 bu/acre in 2021.

## County Data (County_Data sheet, pre-filled)

| County | District | Actual 2022 (bu/ac) | Potential (bu/ac) | Harvested 2022 (acres) |
|--------|----------|---------------------|-------------------|------------------------|
| Delaware | NE | 230.8 | 250 | 161,800 |
| Dubuque | NE | 223.7 | 250 | 134,000 |
| Chickasaw | NE | 214.6 | 250 | 139,800 |
| Clayton | NE | 215.4 | 250 | 128,700 |
| Allamakee | NE | 215.9 | 250 | 76,400 |
| Franklin | NC | 220.1 | 235 | 186,500 |
| Cerro Gordo | NC | 216.9 | 235 | 160,600 |
| Mitchell | NC | 217.9 | 235 | 140,000 |
| Wright | NC | 209.7 | 235 | 171,900 |
| Butler | NC | 212.4 | 235 | 157,800 |
| Hancock | NC | 211.5 | 235 | 168,700 |
| Benton | EC | 221.7 | 246 | 180,800 |
| Cedar | EC | 221.4 | 246 | 147,600 |
| Clinton | EC | 225.2 | 246 | 180,400 |
| Jones | EC | 218.2 | 246 | 144,900 |
| Linn | EC | 215.0 | 246 | 137,700 |
| Scott | EC | 216.2 | 246 | 102,100 |
| Muscatine | EC | 213.1 | 246 | 87,300 |
| Hardin | Central | 215.6 | 242 | 172,600 |
| Pottawattamie | SW | 195.0 | 240 | 233,000 |
| Cass | SW | 179.2 | 215 | 123,900 |
| Adair | SW | 164.2 | 200 | 106,700 |

Total harvested area: 3,237,200 acres across 22 counties.

## Required Analysis

### Yield_Gap_Analysis sheet (agent fills in)

For each county (rows 2–23):
- **Column E — Yield Gap (%)**: `(Potential - Actual) / Potential × 100`
- **Column F — Category**: `IF(E2 >= 13, "High Gap", IF(E2 < 9, "Low Gap", "Medium Gap"))`
- **Column G — Rank**: `RANK(E2, $E$2:$E$23, 1)` — ascending (1 = smallest gap)

Summary row 24:
- **E24**: State area-weighted average yield gap `= SUMPRODUCT(D2:D23, E2:E23) / SUM(D2:D23)`

Expected results:
- Weighted average yield gap: **11.33%** (range 10.0–12.5%)
- High Gap counties (≥13%): **7** (Pottawattamie 18.75%, Adair 17.90%, Cass 16.65%, Chickasaw 14.16%, Clayton 13.84%, Allamakee 13.64%, Muscatine 13.37%)
- Low Gap counties (<9%): **5** (Delaware 7.68%, Franklin 6.34%, Cerro Gordo 7.70%, Mitchell 7.28%, Clinton 8.46%)
- Highest gap county: **Pottawattamie** (18.75%, rank 22)
- Lowest gap county: **Franklin** (6.34%, rank 1)

## Scoring (100 points)

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Yield Gap % values present for ≥18 counties (range 6–22%) | 20 | Column E populated |
| State area-weighted avg yield gap in [10.0%, 12.5%] | 25 | SUMPRODUCT formula correct |
| At least 5 'High Gap' counties labeled | 20 | IF formula with 13% threshold |
| At least 3 'Low Gap' counties labeled | 20 | IF formula with 9% threshold |
| Pottawattamie has highest rank (rank 22 or max) | 15 | RANK formula ascending |

**Pass threshold**: 60 points
**Do-nothing score**: 0 (all output cells blank in starter file)

## Why This Is Hard

- RANK function requires correct range locking (`$E$2:$E$23`) and ascending choice
- SUMPRODUCT weighted average uses pre-filled area column (col D), not cross-sheet reference
- IF nesting for 3-way category requires correct double-threshold handling
- 22 counties × 3 formula columns = 66 cells of formula work plus 1 summary cell
- Two threshold cutoffs (9% and 13%) vs many problems use simpler above/below median splits
- Agent must use col D harvested area as weights in the SUMPRODUCT — not obvious from col headers

## Verification Strategy

1. **is_new check**: Export script records file modification time; verifier gates on is_new
2. **Independent xlsx re-analysis**: Verifier copies xlsx and parses with openpyxl `data_only=True`
3. **Range validation**: Yield gap % values checked to be plausible (6–22% range with real 2022 data)
4. **String matching**: Category labels counted for High Gap / Low Gap
5. **Rank check**: Pottawattamie row (col A) checked for max rank value in col G
