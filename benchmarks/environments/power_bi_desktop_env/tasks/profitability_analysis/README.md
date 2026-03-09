# Task: profitability_analysis

## Overview

A financial controller at a consumer goods company must produce a gross-profit breakdown by product category and region for the CFO's cost review. This task requires authoring non-trivial DAX expressions (SUMX for row-level multiplication, DIVIDE for safe division), configuring a Matrix visual with cross-tab layout, adding a profitability KPI card, and exporting the visual's data as a CSV file — four distinct Power BI skills that must all be completed correctly.

## Data

- **Source**: `C:\Users\Docker\Desktop\PowerBITasks\sales_data.csv` (1000 rows)
- **Key columns used**: Sales_Amount, Quantity_Sold, Unit_Cost, Unit_Price, Product_Category, Region, Discount
- **Product categories**: Electronics, Clothing, Food, Furniture
- **Regions**: North, South, East, West

## Goal

Build and save a Power BI report named `Profitability_Report.pbix` on the Desktop.

**Data model — two DAX measures**:
- `Gross_Profit`: Total sales revenue minus total cost of goods sold. The cost per row is `Quantity_Sold × Unit_Cost`; sum this across all rows and subtract from total `Sales_Amount`.
- `Profit_Margin_Pct`: `Gross_Profit` divided by total `Sales_Amount`, using DIVIDE to guard against zero denominator.

**Visuals**:
- A Matrix visual: Product_Category as rows, Region as columns, `Gross_Profit` as values
- A Card visual: displays `Profit_Margin_Pct`

**CSV export**:
- Right-click the Matrix visual → "Export data" → save as `profit_by_category.csv` on the Desktop

**Output files**:
- `C:\Users\Docker\Desktop\Profitability_Report.pbix`
- `C:\Users\Docker\Desktop\profit_by_category.csv`

## Starting State

- Power BI Desktop is open with a blank canvas
- `sales_data.csv` is available at the PowerBITasks folder on the Desktop
- No prior `Profitability_Report.pbix` or `profit_by_category.csv` exists

## Agent Workflow

1. Import `sales_data.csv` into Power BI
2. Create `Gross_Profit` DAX measure using SUMX for cost aggregation
3. Create `Profit_Margin_Pct` DAX measure using DIVIDE
4. Build a Matrix visual with correct row/column/value assignments
5. Build a Card visual showing Profit_Margin_Pct
6. Right-click the Matrix → Export data → save as `profit_by_category.csv`
7. Save report as `Profitability_Report.pbix`

No UI navigation steps are provided — the agent must discover how to author DAX measures, configure the Matrix visual, and use the Export data feature.

## Success Criteria (100 points total)

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| Report file saved | 15 | `Profitability_Report.pbix` exists on Desktop |
| Gross_Profit measure | 20 | "Gross_Profit" found in data model or layout |
| Profit_Margin_Pct measure | 20 | "Profit_Margin_Pct" found in data model or layout |
| Matrix visual present | 20 | pivotTable/matrix visual type in report layout |
| CSV exported | 25 | `profit_by_category.csv` exists with ≥5 rows and numeric data |

**Pass threshold**: 70 points

## Verification Strategy

1. `export_result.ps1` closes PBI, unzips `Profitability_Report.pbix`, parses `Report/Layout`, checks `DataModel` binary for measure names, and inspects `profit_by_category.csv`
2. `verifier.py` copies `profitability_result.json` from VM and scores each criterion independently

## Anti-Gaming Measures

- Start timestamp recorded; verifier checks file was created after task start
- Baseline confirms no pre-existing target files at setup time
- CSV check verifies numeric profit values, not just file existence
