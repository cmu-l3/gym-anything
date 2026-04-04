# Task: cross_source_analysis

## Overview

A business intelligence analyst at a regional company needs to understand whether regions with higher-performing employees also generate more sales revenue. The challenge: the two data sources use incompatible geographic keys — sales data uses cardinal regions (North/South/East/West) while HR data uses city names. The analyst must build a city-to-region mapping in Power Query, create a table relationship across the resulting common key, author a cross-table DAX measure, and build a Scatter Chart + Matrix to visualize the correlation. This requires chaining five distinct Power BI skills in the correct order, with each step depending on the previous.

## Data

**Table 1 — sales_data.csv**:
- 1000 rows, columns include Region (North/South/East/West), Sales_Amount, Product_Category, Sales_Rep
- `C:\Users\Docker\Desktop\PowerBITasks\sales_data.csv`

**Table 2 — employee_performance.csv**:
- 1000 rows, columns include Location (city names), Department, Salary, Performance Score, Status
- `C:\Users\Docker\Desktop\PowerBITasks\employee_performance.csv`

**Key schema mismatch**: sales uses cardinal directions; employees use city names. Requires Power Query conditional column to create a `Region` column in the employee table.

## Goal

Build and save `Integrated_Analysis.pbix` on the Desktop with:

**Power Query**:
- Import both CSVs as separate tables
- Add conditional column `Region` to employee table mapping cities → cardinal directions:
  - New York, Philadelphia → East
  - Los Angeles, Phoenix, San Diego, San Jose → West
  - Chicago → North
  - Houston, San Antonio, Dallas → South
  - (Anything else → "Other")

**Data Model**:
- Create a relationship: sales_data[Region] ↔ employee_performance[Region]
- DAX measure: `Sales_Per_Head = DIVIDE(SUM(sales_data[Sales_Amount]), COUNTROWS(employee_performance), 0)`

**Report page "Integrated View"**:
- Scatter Chart: average Salary vs total Sales_Amount, by Region
- Matrix: Region as rows, Sales_Amount and avg Performance Score as columns

**Output**: `C:\Users\Docker\Desktop\Integrated_Analysis.pbix`

## Starting State

- Power BI Desktop is open, blank canvas
- Both CSV files in `C:\Users\Docker\Desktop\PowerBITasks\`
- No prior `Integrated_Analysis.pbix` exists

## Agent Workflow

1. Import `sales_data.csv` into Power BI
2. Import `employee_performance.csv` as a second table
3. In Power Query Editor for employee table: add conditional column `Region` (city → direction mapping)
4. Close and apply
5. In Model view: create relationship between sales_data[Region] and employee_performance[Region]
6. Create `Sales_Per_Head` DAX measure
7. Name page "Integrated View"
8. Build Scatter Chart with correct field assignments
9. Build Matrix with Region rows and two value columns
10. Save as `Integrated_Analysis.pbix`

No UI navigation steps provided — the agent must independently navigate Model View, Power Query Editor, and the visualization pane.

## Success Criteria (100 points total)

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| File saved | 15 | `Integrated_Analysis.pbix` exists on Desktop |
| Both tables loaded | 20 | DataMashup M code references both CSV filenames |
| Region conditional column | 20 | "Region" column added in employee Power Query steps |
| Sales_Per_Head measure | 20 | Measure name in data model binary or layout |
| Scatter Chart + Matrix | 25 | Both scatterChart and pivotTable visual types in layout |

**Pass threshold**: 70 points

## Verification Strategy

1. `export_result.ps1` closes PBI, unzips `.pbix`, reads `Report/Layout`, `DataMashup` M code, and `DataModel` binary
2. Checks M code for both CSV filenames (two separate data sources)
3. Checks M code for conditional column / Region mapping
4. Checks model binary and layout for `Sales_Per_Head` measure name
5. Checks layout for scatterChart and pivotTable visual types
6. Writes `cross_source_result.json`

## Anti-Gaming Measures

- Two-source check prevents gaming by loading just one table
- Conditional column check requires non-trivial M code
- Scatter Chart is an unusual choice that requires correct axis configuration
