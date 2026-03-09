# Custom Tooltip Report (`custom_tooltip_report@1`)

## Overview

This task tests the agent's ability to create a Power BI report featuring a **custom tooltip page** — a specially sized page that appears as a rich hover-over detail panel when users interact with visuals on the main report page. The agent must configure page sizing, build mini-visuals on the tooltip page, create a DAX measure, and connect the tooltip page to main-page visuals.

## Rationale

**Why this task is valuable:**
- Tests a unique Power BI capability (custom tooltip pages)
- Requires understanding of page type configuration (tooltip vs. standard page sizing)
- Combines DAX measure authoring with visual layout across two coordinated pages
- Validates knowledge of visual-level tooltip assignment

**Real-world Context:** A product marketing manager needs a compact sales overview. When presenters hover over any product category bar, a rich tooltip should pop up showing price points and payment breakdowns, eliminating the need to switch pages during a meeting.

## Task Description

**Goal:** Build and save a two-page Power BI Desktop report named `Tooltip_Report.pbix` on the Desktop, where the second page is configured as a **Tooltip page** and is linked as the custom tooltip for visuals on the main page.

**Starting State:**
- Power BI Desktop is open with a blank report canvas
- `sales_data.csv` is available at `C:\Users\Docker\Desktop\PowerBITasks\sales_data.csv`
- No prior `Tooltip_Report.pbix` exists on the Desktop

**Expected Actions:**
1. Import `sales_data.csv` into Power BI Desktop.
2. Create a DAX measure named `Avg_Unit_Price` that computes `AVERAGE(sales_data[Unit_Price])`.
3. Rename the first page to **"Sales Overview"** and add:
   - A **Clustered Column Chart** (`Product_Category` vs `Sales_Amount`)
   - A **Line Chart** (`Sale_Date` vs `Sales_Amount`)
4. Create a second page named **"Category Detail"**, set Page Size to **Tooltip**, and add:
   - A **Card** visual for `Avg_Unit_Price`
   - A **Card** visual for `Quantity_Sold`
   - A **Stacked Bar Chart** (`Payment_Method` vs `Sales_Amount`)
5. Enable **"Allow use as tooltip"** on the "Category Detail" page.
6. Configure the Clustered Column Chart on Page 1 to use "Category Detail" as its tooltip.
7. Save the report as `Tooltip_Report.pbix` on the Desktop.

## Verification Strategy

### Primary Verification: Layout JSON Parsing
The verifier unzips the `.pbix` file and parses the `Report/Layout` JSON to check:
- Existence of two pages with correct names.
- Dimensions of the "Category Detail" page (must be small, approx 320x240).
- Presence of specific visual types on each page.
- Existence of the `Avg_Unit_Price` measure in the data model.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| File saved | 10 | `Tooltip_Report.pbix` exists and created during task |
| "Sales Overview" page | 10 | Page exists |
| "Category Detail" page | 10 | Page exists |
| Tooltip sizing | 20 | "Category Detail" page has tooltip dimensions (width < 500) |
| Visuals (Page 1) | 15 | Clustered Column and Line charts present |
| Visuals (Page 2) | 15 | Two Cards and Stacked Bar chart present |
| DAX Measure | 20 | "Avg_Unit_Price" found in data model |
| **Total** | **100** | |