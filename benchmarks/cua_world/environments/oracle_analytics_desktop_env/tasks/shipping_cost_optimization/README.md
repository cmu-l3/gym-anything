# Task: shipping_cost_optimization

## Overview

**Difficulty:** very_hard
**Environment:** Oracle Analytics Desktop (Windows 11)
**Persona:** VP of Operations at FastFlow Distribution
**Domain:** Logistics / Supply Chain Analytics

The logistics team needs a Shipping Cost Optimization Dashboard to identify which shipping modes erode margin. The analyst must build a multi-canvas OAD workbook analyzing shipping costs, mode efficiency, and profitability — including a custom shipping ratio KPI.

## Goal

Build and save an Oracle Analytics workbook named `shipping_optimization.dva` in `C:\Users\Docker\Documents\`, containing exactly three canvases with specific names and a calculated column. No UI navigation hints are provided.

## Required Outputs

**Workbook file:** `C:\Users\Docker\Documents\shipping_optimization.dva`

**Canvas 1 — `Shipping Overview`**
- Analyzes total Shipping Cost across Ship Mode categories

**Canvas 2 — `Mode Efficiency Matrix`**
- Analyzes Shipping Cost and revenue efficiency by Ship Mode and Customer Segment
- Calculated column `Shipping_Ratio`: `Shipping Cost / Sales`

**Canvas 3 — `Profitability by Mode`**
- Analyzes total Profit and average Shipping_Ratio by Ship Mode

**Data source:** `C:\Users\Docker\Desktop\OracleAnalyticsData\order_lines.csv`

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| Workbook file exists and was created after task start | 20 | File mtime > task start timestamp |
| File is a valid DVA (ZIP) archive | 15 | zipfile.is_zipfile() |
| Canvas 'Shipping Overview' present | 15 | Text search in decompressed .arc |
| Canvas 'Mode Efficiency Matrix' present | 15 | Text search in decompressed .arc |
| Canvas 'Profitability by Mode' present | 15 | Text search in decompressed .arc |
| Calculated column 'Shipping_Ratio' defined | 20 | Text search in decompressed .arc |
| **Total** | **100** | |

**Pass threshold:** 60 points

## Verification Strategy

The `export_result.ps1` script runs post-task and:
1. Reads the task start timestamp from `C:\Users\Docker\task_start_ts_ship_opt.txt`
2. Searches known locations for `shipping_optimization.dva`
3. Writes a result JSON to `C:\Users\Docker\shipping_cost_optimization_result.json`

The `verify_shipping_cost_optimization()` function:
1. Copies the result JSON from the VM
2. Checks file existence and `is_new` flag (mtime > task_start)
3. Copies the DVA file from the VM
4. Decompresses `.arc` entries using `zlib.decompress()` (canvas/column names live here)
5. Searches combined text for exact canvas names and column identifier (case-insensitive)

## Data Schema Reference

**File:** `order_lines.csv` (Tableau Superstore — US market, ~9000 rows)

| Column | Type | Notes |
|--------|------|-------|
| Ship Mode | string | Express Air, Regular Air, Delivery Truck |
| Customer Segment | string | Consumer, Corporate, Home Office, Small Business |
| Shipping Cost | numeric | Shipping cost per order line |
| Sales | numeric | Revenue per order line |
| Profit | numeric | Net profit per order line |
| Product Category | string | Furniture, Office Supplies, Technology |
| Order Priority | string | Critical, High, Medium, Low |

## Edge Cases

- DVA files are ZIP archives containing `.arc` files (zlib-compressed). Canvas names and calculated column identifiers are in `.arc` entries — plain JSON search misses them.
- The workbook must be saved AFTER the task start timestamp. Pre-existing workbooks are cleaned up by `setup_task.ps1`.
- `Shipping_Ratio` carries 20 pts (not 10) as it is the single critical KPI for this logistics task.
- The export script scans `Documents\`, `Desktop\`, and the home directory for the DVA file.
