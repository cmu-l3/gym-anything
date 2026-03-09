# Task: sales_kpi_dashboard

## Overview

A sales operations analyst at a regional consumer goods company must prepare the quarterly business review deck. Management needs a two-page KPI dashboard in Power BI showing an executive summary of overall performance and a regional breakdown with filtering capability. This task requires chaining four distinct Power BI features: multi-page report layout, multiple visual types (Card, Donut, Clustered Bar, Slicer), DAX measure authoring, and field assignment across pages.

## Data

- **Source**: `C:\Users\Docker\Desktop\PowerBITasks\sales_data.csv` (1000 rows)
- **Columns**: Product_ID, Sale_Date, Sales_Rep, Region, Sales_Amount, Quantity_Sold, Product_Category, Unit_Cost, Unit_Price, Customer_Type, Discount, Payment_Method, Sales_Channel, Region_and_Sales_Rep
- **Regions**: North, South, East, West
- **Product categories**: Electronics, Clothing, Food, Furniture

## Goal

Build and save a two-page Power BI Desktop report named `Sales_KPI_Dashboard.pbix` on the Desktop.

**Page 1 — "Overview"**: Executive summary with:
- A Card visual showing total Sales_Amount
- A Card visual showing total Quantity_Sold
- A Donut chart showing Sales_Amount by Product_Category

**Page 2 — "Regional Detail"**: Drill-down view with:
- A Clustered Bar Chart of Sales_Amount by Region, with Sales_Rep as legend/series
- A Slicer for the Sales_Channel column

**Data model**: Two DAX measures named exactly `Total_Revenue` (SUM of Sales_Amount) and `Total_Units` (SUM of Quantity_Sold).

## Starting State

- Power BI Desktop is open with a blank canvas
- `sales_data.csv` is available at `C:\Users\Docker\Desktop\PowerBITasks\sales_data.csv`
- No prior `.pbix` file named `Sales_KPI_Dashboard.pbix` exists

## Agent Workflow (what needs to happen)

The agent must:
1. Import `sales_data.csv` into Power BI Desktop
2. Create two DAX measures in the data model
3. Create two report pages with specific names
4. Build and configure five visuals across two pages with correct field assignments
5. Save the finished report as `Sales_KPI_Dashboard.pbix` on the Desktop

The agent must discover which Power BI features to use and how to configure them. No UI navigation steps are provided.

## Success Criteria (100 points total)

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| File saved | 15 | `Sales_KPI_Dashboard.pbix` exists on Desktop |
| Page count and names | 20 | Report has ≥2 pages named "Overview" and "Regional Detail" |
| Overview page visuals | 20 | Has card and donutChart visual types on any page |
| Regional page visuals | 20 | Has clusteredBarChart and slicer visual types |
| DAX measures in model | 25 | "Total_Revenue" and "Total_Units" appear in the data model |

**Pass threshold**: 70 points

## Verification Strategy

1. `export_result.ps1` closes PBI, then unzips `Sales_KPI_Dashboard.pbix` as a ZIP archive
2. Parses `Report/Layout` JSON to extract page names and visual types
3. Searches `DataModel` binary for measure name strings
4. Writes findings to `C:\Users\Docker\Desktop\sales_kpi_result.json`
5. `verifier.py` copies result JSON from VM and applies scoring

## Anti-Gaming Measures

- Setup records a start timestamp and verifies no target .pbix exists before the agent starts
- Verifier checks that the file was NOT present at setup time (baseline check)
- Visual type check requires correct Power BI visual type identifiers, not just any file
- Measure name check requires specific strings in the data model binary
