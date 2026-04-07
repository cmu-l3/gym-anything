# Task: fulfillment_analytics_dashboard

## Overview

**Difficulty:** very_hard
**Environment:** Oracle Analytics Desktop (Windows 11)
**Persona:** Senior Business Intelligence Engineer at LogiQuant Technologies
**Domain:** Operations / Fulfillment Analytics

The operations team needs a comprehensive Order Fulfillment Analytics Dashboard to optimize workflows by order priority and product container type. The analyst must build a multi-canvas OAD workbook covering priority-level sales analysis, profitability by priority, and container-type cost efficiency — with two custom calculated KPIs.

## Goal

Build and save an Oracle Analytics workbook named `fulfillment_analytics.dva` in `C:\Users\Docker\Documents\`, containing exactly three canvases with specific names and calculated columns. No UI navigation hints are provided.

## Required Outputs

**Workbook file:** `C:\Users\Docker\Documents\fulfillment_analytics.dva`

**Canvas 1 — `Priority Breakdown`**
- Analyzes total Sales by Order Priority
- Calculated column `Revenue_Per_Line`: `Sales / Quantity Ordered`

**Canvas 2 — `Priority Profitability`**
- Analyzes total Profit and average Revenue_Per_Line by Order Priority

**Canvas 3 — `Container Fulfillment`**
- Analyzes total Shipping Cost and total Sales by Product Container type
- Calculated column `Fulfillment_Margin`: `(Sales - Shipping Cost) / Sales`

**Data source:** `C:\Users\Docker\Desktop\OracleAnalyticsData\order_lines.csv`

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| Workbook file exists and was created after task start | 20 | File mtime > task start timestamp |
| File is a valid DVA (ZIP) archive | 15 | zipfile.is_zipfile() |
| Canvas 'Priority Breakdown' present | 15 | Text search in decompressed .arc |
| Canvas 'Priority Profitability' present | 15 | Text search in decompressed .arc |
| Canvas 'Container Fulfillment' present | 15 | Text search in decompressed .arc |
| Calculated column 'Revenue_Per_Line' defined | 10 | Text search in decompressed .arc |
| Calculated column 'Fulfillment_Margin' defined | 10 | Text search in decompressed .arc |
| **Total** | **100** | |

**Pass threshold:** 60 points

## Verification Strategy

The `export_result.ps1` script runs post-task and:
1. Reads the task start timestamp from `C:\Users\Docker\task_start_ts_fulfillment.txt`
2. Searches known locations for `fulfillment_analytics.dva`
3. Writes a result JSON to `C:\Users\Docker\fulfillment_analytics_dashboard_result.json`

The `verify_fulfillment_analytics_dashboard()` function:
1. Copies the result JSON from the VM
2. Checks file existence and `is_new` flag (mtime > task_start)
3. Copies the DVA file from the VM
4. Decompresses `.arc` entries using `zlib.decompress()` (canvas/column names live here)
5. Searches combined text for exact canvas names and column identifiers (case-insensitive)

## Data Schema Reference

**File:** `order_lines.csv` (Tableau Superstore — US market, ~9000 rows)

| Column | Type | Notes |
|--------|------|-------|
| Order Priority | string | Critical, High, Medium, Low |
| Product Container | string | Jumbo Box, Large Box, Medium Box, Small Box, Wrap Bag |
| Sales | numeric | Revenue per order line |
| Profit | numeric | Net profit per order line |
| Shipping Cost | numeric | Shipping cost per order line |
| Quantity Ordered | integer | Units ordered |
| Ship Mode | string | Express Air, Regular Air, Delivery Truck |
| Customer Segment | string | Consumer, Corporate, Home Office, Small Business |
| Product Category | string | Furniture, Office Supplies, Technology |

## Edge Cases

- DVA files are ZIP archives containing `.arc` files (zlib-compressed). Canvas names and calculated column identifiers are in `.arc` entries — plain JSON search misses them.
- The workbook must be saved AFTER the task start timestamp. Pre-existing workbooks are cleaned up by `setup_task.ps1`.
- Both calculated columns (`Revenue_Per_Line` and `Fulfillment_Margin`) must be accessible across canvases; OAD stores them globally in the dataset's calculated columns list.
- The export script scans `Documents\`, `Desktop\`, and the home directory for the DVA file, including a secondary scan for any DVA matching "fulfillment|analytics|priority|container".
