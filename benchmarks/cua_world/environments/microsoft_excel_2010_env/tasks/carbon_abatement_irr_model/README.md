# Carbon Abatement IRR Model

**Environment**: microsoft_excel_2010_env
**Difficulty**: Very Hard
**Occupation**: Sustainability Specialist / Environmental Compliance Manager (SOC 13-1199)
**Industry**: Manufacturing / Corporate Sustainability

## Task Overview

The agent receives a multi-facility GHG inventory and carbon abatement project analysis workbook (`facility_emissions.xlsx`). The workbook contains energy consumption data for four manufacturing facilities in Ohio, Pennsylvania, Illinois, and Massachusetts, along with EPA emission factors and specifications for three capital projects. Three sheets require completion: a GHG inventory calculation (`Emissions_Summary`), and an NPV/IRR project analysis (`Project_IRR`).

## Domain Context

Corporate GHG reporting under SEC Climate Disclosure Rules and voluntary frameworks (GHG Protocol, CDP) requires organizations to calculate Scope 1 (direct) and Scope 2 (purchased electricity) emissions using jurisdiction-specific emission factors. EPA's eGRID database provides electricity emission factors by NERC subregion. Carbon pricing ($50/MT CO2e is a common internal carbon price used for capital project evaluation) translates emissions into financial terms. NPV and IRR analysis using Excel's `NPV()` and `IRR()` functions is the standard method for evaluating energy efficiency investments.

## Data Sources

**EPA GHG Emission Factors** (Facility_Data sheet, rows 11–19):
- Natural Gas: 53.06 kg CO2/MMBtu = **0.05306 MT CO2e/MMBtu**
  - Source: EPA 40 CFR Part 98, Subpart C — Table C-1, Natural Gas (Weighted U.S. Average)
  - URL: https://www.ecfr.gov/current/title-40/chapter-I/subchapter-C/part-98/subpart-C
- Diesel: 10.21 kg CO2/gallon ≈ **0.01020 MT CO2e/gallon**
  - Source: EPA 40 CFR Part 98, Subpart C — Table C-1, Distillate Fuel Oil No. 2 (diesel)
- Electricity — eGRID RFCW subregion (OH/PA/IL): **0.000380 MT CO2e/kWh**
  - Source: EPA eGRID 2022, Subregion RFCW (RFC West) CO2e output emission rate
  - eGRID 2022: ~0.8386 lb CO2e/kWh ÷ 2204.62 lb/MT = 0.000381 MT CO2e/kWh
  - URL: https://www.epa.gov/egrid/download-data (eGRID2022_summary_tables.xlsx, tab "SRL22")
- Electricity — eGRID NEWE subregion (MA): **0.000218 MT CO2e/kWh**
  - Source: EPA eGRID 2022, Subregion NEWE (New England) CO2e output emission rate
  - eGRID 2022: ~0.4804 lb CO2e/kWh ÷ 2204.62 lb/MT = 0.000218 MT CO2e/kWh

**Facility Energy Consumption** (Facility_Data sheet, rows 4–7):
- Energy consumption volumes (kWh, MMBtu, gallons) represent a representative multi-facility manufacturing company
- Electricity volumes are typical for industrial facilities of their class (US EIA CBECS 2018: median 1.8 M kWh/yr for mid-size manufacturing buildings; R&D campuses 2–5× higher)
- Natural gas and diesel volumes are consistent with EPA Mandatory Reporting Rule thresholds (6-facility programs averaging ~2,500 MT CO2e)

**Carbon Pricing**:
- $50/MT CO2e internal carbon price: Consistent with RGGI 2022 allowance prices ($13–$15), EPA's interim SC-CO2 value ($51/ton in 2021 USD, Biden Admin), and the range commonly used in Fortune 500 internal carbon budgets (CDP 2023 Global Report: median internal carbon price = $50/MT for manufacturing sector)

## Data

**Facility_Data sheet** (pre-filled):

| Facility | State | Electricity (kWh) | Natural Gas (MMBtu) | Diesel (gal) | Refrigerants (MT) |
|----------|-------|------------------|---------------------|--------------|-------------------|
| HQ Campus | OH | 4,250,000 | 18,500 | 42,000 | 8.2 |
| East Distribution | PA | 1,820,000 | 7,200 | 95,000 | 3.1 |
| West Warehouse | IL | 2,340,000 | 9,100 | 78,000 | 4.7 |
| R&D Center | MA | 3,100,000 | 12,400 | 15,000 | 1.8 |

EPA emission factors (provided in sheet, rows 11–19):
- Natural Gas: 0.05306 MT CO2e/MMBtu
- Diesel: 0.01020 MT CO2e/gallon
- eGRID RFCW (OH/PA/IL): 0.000380 MT CO2e/kWh
- eGRID NEWE (MA): 0.000218 MT CO2e/kWh

## Required Analysis

### Emissions_Summary sheet (agent fills in)

For each of 4 facilities:
- Scope 1 NatGas, Scope 1 Diesel, Scope 1 Refrigerants, Total Scope 1
- Scope 2 Electricity (using correct regional factor per state)
- Total Scope 1+2, Carbon Cost at $50/MT CO2e

Company totals (row 9):
- **Total Scope 1+2**: ~8,740 MT CO2e
- **Carbon Cost**: ~$436,992
- **Emissions Intensity per FTE** (~4.97 MT/FTE) and per sq ft

### Project_IRR sheet (agent fills in)

Three abatement projects (results table rows 19–21):

| Project | CapEx | Elec Savings | Gas Savings | Life | Annual O&M |
|---------|-------|-------------|-------------|------|------------|
| LED Lighting | $185,000 | 320,000 kWh | 0 | 10yr | $4,200 |
| HVAC Upgrade | $420,000 | 280,000 kWh | 2,100 MMBtu | 15yr | $8,500 |
| Rooftop Solar | $650,000 | 840,000 kWh | 0 | 25yr | $12,000 |

For each project (using assumptions: $0.112/kWh, $8.50/MMBtu, 8% WACC):
- Annual Energy Savings ($), Annual Carbon Savings (MT), Annual Carbon Value ($)
- Net Annual Benefit = Energy Savings + Carbon Value − O&M
- **NPV at 8%** using Excel `=NPV(0.08, cash_flow_range)` or annuity formula
- **IRR** using Excel `=IRR(cash_flow_array)` with year-0 = −CapEx
- **Simple Payback** = CapEx / Net Annual Benefit

Expected results:
- LED IRR: ~15.6%, NPV: ~$68,104
- HVAC IRR: ~8.8%, NPV: ~$21,680
- Solar IRR: ~14.6%, NPV: ~$396,555

## Scoring (100 points)

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Company total Scope 1+2 in [8,300, 9,200] MT CO2e | 25 | Correct scope calculation |
| Company carbon cost in [$415K, $460K] | 20 | Correct $50/MT × totals |
| LED Lighting NPV in [$50K, $90K] | 20 | Correct NPV formula |
| Rooftop Solar NPV in [$340K, $455K] | 20 | Correct NPV over 25yr life |
| At least 2 valid IRR values in [5%, 25%] | 15 | IRR() function used correctly |

**Pass threshold**: 60 points
**Do-nothing score**: 0 (all output cells blank in starter file)

## Why This Is Hard

- Requires different Scope 2 factors for MA (NEWE) vs OH/PA/IL (RFCW) — agent must identify state
- NPV formula with Excel's `NPV()` function takes future cash flows only; year-0 added separately
- IRR requires building a cash flow column (negative CapEx in year 0, benefits in years 1–N)
- Project lives differ (10/15/25 years) — agent must build correctly sized cash flow ranges
- Intensity metrics require totaling FTE and sqft across facilities (cross-row aggregation)
- 4 facilities × 9 columns + 3 projects × 8 columns = significant formula work

## Verification Strategy

1. **is_new check**: Export script records file modification time; verifier gates on is_new
2. **Independent xlsx re-analysis**: Verifier copies xlsx and parses with openpyxl `data_only=True`
3. **Range validation**: Total Scope 1+2 and carbon cost checked against expected ranges
4. **NPV range check**: LED and Solar NPV checked against computed expected values ±30%
5. **IRR detection**: IRR values detected as decimals (0.05–0.25) or percentages (5–25%)
