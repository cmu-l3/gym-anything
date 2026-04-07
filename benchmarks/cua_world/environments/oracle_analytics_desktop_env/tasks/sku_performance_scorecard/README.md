# Task: sku_performance_scorecard

## Overview

**Difficulty:** very_hard
**Environment:** Oracle Analytics Desktop (Windows 11)
**Persona:** Director of Product Strategy at NovaTrade Commerce
**Domain:** Product Management / Retail Analytics

The board has requested a SKU Performance Scorecard to rationalize the product catalog and identify underperforming lines. The analyst must build a multi-canvas OAD workbook covering category/mode performance matrices, gross margin ranking, and container-level cost analysis — with two custom calculated columns.

## Goal

Build and save an Oracle Analytics workbook named `sku_performance.dva` in `C:\Users\Docker\Documents\`, containing exactly three canvases with specific names and calculated columns. No UI navigation hints are provided.

## Required Outputs

**Workbook file:** `C:\Users\Docker\Documents\sku_performance.dva`

**Canvas 1 — `Category Scorecard`**
- Analyzes total Sales and total Profit across Product Category and Ship Mode combinations

**Canvas 2 — `Margin Leaders`**
- Analyzes Product Category performance by gross margin
- Calculated column `Gross_Margin_Pct`: `(Sales - Shipping Cost) / Sales * 100`

**Canvas 3 — `Container Performance`**
- Analyzes total Sales and total Shipping Cost by Product Container type
- Calculated column `Margin_After_Ship`: `Sales - Shipping Cost`

**Data source:** `C:\Users\Docker\Desktop\OracleAnalyticsData\sample_order_lines2023.xlsx`

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| Workbook file exists and was created after task start | 20 | File mtime > task start timestamp |
| File is a valid DVA (ZIP) archive | 15 | zipfile.is_zipfile() |
| Canvas 'Category Scorecard' present | 15 | Text search in decompressed .arc |
| Canvas 'Margin Leaders' present | 15 | Text search in decompressed .arc |
| Canvas 'Container Performance' present | 15 | Text search in decompressed .arc |
| Calculated column 'Gross_Margin_Pct' defined | 10 | Text search in decompressed .arc |
| Calculated column 'Margin_After_Ship' defined | 10 | Text search in decompressed .arc |
| **Total** | **100** | |

**Pass threshold:** 60 points

## Verification Strategy

The `export_result.ps1` script runs post-task and:
1. Reads the task start timestamp from `C:\Users\Docker\task_start_ts_sku_perf.txt`
2. Searches known locations for `sku_performance.dva`
3. Writes a result JSON to `C:\Users\Docker\sku_performance_scorecard_result.json`

The `verify_sku_performance_scorecard()` function:
1. Copies the result JSON from the VM
2. Checks file existence and `is_new` flag (mtime > task_start)
3. Copies the DVA file from the VM
4. Decompresses `.arc` entries using `zlib.decompress()` (canvas/column names live here)
5. Searches combined text for exact canvas names and column identifiers (case-insensitive)

## Data Schema Reference

**File:** `sample_order_lines2023.xlsx` (Global retail orders — international markets; ~9000 rows)

| Column | Type | Notes |
|--------|------|-------|
| Product Category | string | Office Supplies, Furniture, Technology |
| Product Sub Category | string | Finer product groupings |
| Product Container | string | Jumbo Box, Large Box, Medium Box, Small Box, Wrap Bag |
| Product Name | string | Individual SKU names |
| Ship Mode | string | Express Air, Regular Air, Delivery Truck |
| Sales | numeric | Revenue per order line |
| Profit | numeric | Net profit per order line |
| Shipping Cost | numeric | Shipping cost per order line |
| Quantity Ordered | integer | Units ordered |
| Customer Segment | string | Consumer, Corporate, Home Office |

## Data Diversity Note

This task uses `sample_order_lines2023.xlsx` (global market data) rather than `order_lines.csv` (US Superstore data). The datasets share the same schema but contain entirely different order records from different geographic markets, providing data diversity across the benchmark tasks.

## Edge Cases

- DVA files are ZIP archives containing `.arc` files (zlib-compressed). Canvas names and calculated column identifiers are in `.arc` entries — plain JSON search misses them.
- The workbook must be saved AFTER the task start timestamp. Pre-existing workbooks are cleaned up by `setup_task.ps1`.
- The Excel file must be loaded as a dataset in OAD (File > Add Dataset, select the .xlsx file).
- The export script scans `Documents\`, `Desktop\`, and the home directory for the DVA file.
