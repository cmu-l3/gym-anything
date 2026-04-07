# Task: pl_attribution_dashboard

## Overview

**Difficulty:** very_hard
**Environment:** Oracle Analytics Desktop (Windows 11)
**Persona:** Senior Financial Analyst at Meridian Retail Group
**Domain:** Corporate Finance / Business Intelligence

The CFO has requested a Profit & Loss Attribution Dashboard ahead of a board presentation. The analyst must build a multi-canvas OAD workbook that breaks down profitability across customer segments and product categories, including custom calculated KPIs.

## Goal

Build and save an Oracle Analytics workbook named `pl_attribution.dva` in `C:\Users\Docker\Documents\`, containing exactly three canvases with specific names and calculated columns. The agent must discover how to create workbooks, add canvases, define calculated columns, and save the artifact — no UI navigation hints are provided.

## Required Outputs

**Workbook file:** `C:\Users\Docker\Documents\pl_attribution.dva`

**Canvas 1 — `Segment Profitability`**
- Analyzes total Sales and total Profit by Customer Segment

**Canvas 2 — `Category Margin Analysis`**
- Analyzes total Sales and profit margin by Product Category
- Calculated column `Profit_Margin_Pct`: `Profit / Sales * 100`

**Canvas 3 — `Unit Economics`**
- Analyzes product category and customer segment economics
- Calculated column `Net_Profit_Per_Unit`: `Profit / Quantity Ordered`

**Data source:** `C:\Users\Docker\Desktop\OracleAnalyticsData\order_lines.csv`

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| Workbook file exists and was created after task start | 20 | File mtime > task start timestamp |
| File is a valid DVA (ZIP) archive | 15 | zipfile.is_zipfile() |
| Canvas 'Segment Profitability' present | 15 | Text search in decompressed .arc |
| Canvas 'Category Margin Analysis' present | 15 | Text search in decompressed .arc |
| Canvas 'Unit Economics' present | 15 | Text search in decompressed .arc |
| Calculated column 'Profit_Margin_Pct' defined | 10 | Text search in decompressed .arc |
| Calculated column 'Net_Profit_Per_Unit' defined | 10 | Text search in decompressed .arc |
| **Total** | **100** | |

**Pass threshold:** 60 points

## Verification Strategy

The `export_result.ps1` script runs post-task and:
1. Reads the task start timestamp from `C:\Users\Docker\task_start_ts_pl_attr.txt`
2. Searches known locations for `pl_attribution.dva`
3. Writes a result JSON to `C:\Users\Docker\pl_attribution_dashboard_result.json`

The `verify_pl_attribution_dashboard()` function:
1. Copies the result JSON from the VM
2. Checks file existence and `is_new` flag (mtime > task_start)
3. Copies the DVA file from the VM
4. Decompresses `.arc` entries using `zlib.decompress()` (canvas/column names live here)
5. Searches combined text for exact canvas names and column identifiers (case-insensitive)

## Data Schema Reference

**File:** `order_lines.csv` (Tableau Superstore — US market, ~9000 rows)

| Column | Type | Notes |
|--------|------|-------|
| Customer Segment | string | Consumer, Corporate, Home Office, Small Business |
| Product Category | string | Furniture, Office Supplies, Technology |
| Sales | numeric | Revenue per order line |
| Profit | numeric | Net profit per order line |
| Shipping Cost | numeric | Shipping cost per order line |
| Quantity Ordered | integer | Units ordered |
| Discount | numeric | Discount fraction (0.0–1.0) |
| Ship Mode | string | Express Air, Regular Air, Delivery Truck |
| Product Container | string | Jumbo Box, Large Box, Medium Box, Small Box, Wrap Bag |
| Order Priority | string | Critical, High, Medium, Low |

## Edge Cases

- DVA files are ZIP archives containing `.arc` files (zlib-compressed) alongside `.json` files. Canvas names and calculated column identifiers are stored in the `.arc` entries — plain JSON search misses them.
- The workbook must be saved AFTER the task start timestamp. Pre-existing workbooks with the same name are cleaned up by `setup_task.ps1`.
- Column names in the verifier search are case-insensitive; the DVA stores them with exact casing as entered by the agent.
- The export script scans `Documents\`, `Desktop\`, and the home directory for the DVA file.
