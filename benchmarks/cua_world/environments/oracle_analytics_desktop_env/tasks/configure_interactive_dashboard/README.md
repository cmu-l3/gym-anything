# Configure Interactive Regional Dashboard (`configure_interactive_dashboard@1`)

## Overview
This task evaluates the agent's ability to create an **interactive master-detail dashboard** in Oracle Analytics Desktop. The agent must build a summary chart and a detail table, then configure the summary chart to act as a filter ("Use as Filter") for the table. This tests dashboard design skills and the ability to implement interactivity, which is essential for self-service business intelligence.

## Rationale
**Why this task is valuable:**
- **Beyond Static Charts:** Tests the ability to create dynamic, interactive reports rather than static views.
- **Master-Detail Logic:** Validates understanding of how to link high-level metrics to granular data.
- **Application UX:** Requires using visualization properties (specifically the "Use as Filter" interaction) to improve user experience.
- **Drill-Down Analysis:** Simulates a real-world workflow where managers identify a trend and immediately investigate the underlying transactions.

**Real-world Context:** A Regional Operations Manager needs a dashboard to review quarterly performance. They want to click on a specific Region (e.g., "East") in a summary chart and immediately see the detailed list of customer orders for that region to investigate anomalies, without having to apply manual filters repeatedly.

## Task Description

**Goal:** Create a dashboard with a **Region Sales Summary** bar chart and a **Customer Order Details** table, configure the bar chart to filter the table upon selection, filter for the "East" region, and save the workbook.

**Starting State:**
- Oracle Analytics Desktop is open.
- The built-in `Sample Order Lines` dataset is available.
- The canvas is empty.

**Expected Actions:**
1. **Create Summary Visualization:**
   - Create a **Bar Chart**.
   - Drag **Region** to the Category (X-axis) axis.
   - Drag **Sales** to the Values (Y-axis) axis.
   - Title this chart: **"Regional Sales Summary"**.

2. **Create Detail Visualization:**
   - Create a **Table** visualization on the same canvas (next to or below the chart).
   - Add the following columns: **Customer Name**, **Order ID**, **Sales**, **Profit**.
   - Title this table: **"Order Details"**.

3. **Configure Interactivity:**
   - Select the **"Regional Sales Summary"** bar chart.
   - Enable the **"Use as Filter"** option (often a funnel icon in the visualization toolbar or right-click menu options). This ensures that clicking a bar filters other visualizations on the canvas.

4. **Demonstrate Interactivity:**
   - Click the bar for the **"East"** region in the "Regional Sales Summary" chart.
   - Verify that the "Order Details" table updates to show only data relevant to the East region (row count should decrease).

5. **Save:**
   - Save the workbook as **`Regional_Drilldown`** (resulting in `Regional_Drilldown.dva`).

**Final State:**
- A workbook named `Regional_Drilldown.dva` exists.
- The canvas displays two visualizations: a bar chart and a table.
- The "East" region is currently selected/highlighted in the bar chart.
- The table displays data filtered to the "East" region.

## Verification Strategy

### Primary Verification: VLM Visual Analysis
The verifier analyzes the final state and trajectory screenshots:
1. **Layout Check:** Confirms presence of two distinct visualizations (Bar Chart and Table) on the canvas.
2. **Interaction State:** Verifies that the "East" bar is visually selected (highlighted/different color than others).
3. **Filtering Evidence:** Checks that the table content reflects the selection (shows fewer rows or specific East data).
4. **"Use as Filter" Indicator:** Detects the active state of the filter icon on the summary chart toolbar if visible.

### Secondary Verification: Workbook File Inspection
The `.dva` file (ZIP archive) is extracted to verify internal structure:
1. **File Existence:** `Regional_Drilldown.dva` exists and is a valid archive.
2. **Visualization Count:** Metadata confirms exactly two visualizations on the active canvas.
3. **Data Mapping:** Checks for required columns in the XML definition.
4. **Interaction Config:** Checks the visualization metadata for filter interaction settings.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| **File Created** | 10 | `Regional_Drilldown.dva` saved successfully. |
| **Summary Chart** | 15 | Bar chart with Region and Sales created correctly. |
| **Detail Table** | 15 | Table with Customer, Order ID, Sales, Profit created. |
| **Interactivity Config** | 20 | "Use as Filter" enabled (verified via file metadata or VLM). |
| **Selection State** | 20 | "East" region is selected in final view (VLM). |
| **Table Filtered** | 20 | Table shows filtered results corresponding to selection (VLM). |
| **Total** | **100** | |

**Pass Threshold:** 60 points (Must have created dashboard and attempted interaction).