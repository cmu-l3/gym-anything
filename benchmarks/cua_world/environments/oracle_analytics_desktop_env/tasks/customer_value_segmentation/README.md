# Task: customer_value_segmentation

## Overview

**Difficulty:** very_hard
**Environment:** Oracle Analytics Desktop (Windows 11)
**Persona:** Senior Market Research Analyst at Apex Consumer Insights
**Domain:** Market Research / Customer Analytics

A retail client has engaged Apex Consumer Insights to segment their global customer base by lifetime value and revenue contribution. The analyst must build a multi-canvas OAD workbook covering revenue mix, value relationships, and discount impact by customer segment — using two custom calculated KPIs.

## Goal

Build and save an Oracle Analytics workbook named `customer_value_segmentation.dva` in `C:\Users\Docker\Documents\`, containing exactly three canvases with specific names and calculated columns. No UI navigation hints are provided.

## Required Outputs

**Workbook file:** `C:\Users\Docker\Documents\customer_value_segmentation.dva`

**Canvas 1 — `Revenue Mix`**
- Analyzes total Sales distribution across Customer Segments

**Canvas 2 — `Value Scatter`**
- Analyzes relationship between Sales and Profit by Customer Segment
- Calculated column `Customer_LTV`: `Sales - Shipping Cost - (Sales * Discount)`

**Canvas 3 — `Discount Impact`**
- Analyzes Discount behavior and order value by Customer Segment
- Calculated column `Order_Value_Index`: `Sales / Quantity Ordered`

**Data source:** `C:\Users\Docker\Desktop\OracleAnalyticsData\sample_order_lines2023.xlsx`

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| Workbook file exists and was created after task start | 20 | File mtime > task start timestamp |
| File is a valid DVA (ZIP) archive | 15 | zipfile.is_zipfile() |
| Canvas 'Revenue Mix' present | 15 | Text search in decompressed .arc |
| Canvas 'Value Scatter' present | 15 | Text search in decompressed .arc |
| Canvas 'Discount Impact' present | 15 | Text search in decompressed .arc |
| Calculated column 'Customer_LTV' defined | 10 | Text search in decompressed .arc |
| Calculated column 'Order_Value_Index' defined | 10 | Text search in decompressed .arc |
| **Total** | **100** | |

**Pass threshold:** 60 points

## Verification Strategy

The `export_result.ps1` script runs post-task and:
1. Reads the task start timestamp from `C:\Users\Docker\task_start_ts_cust_val_seg.txt`
2. Searches known locations for `customer_value_segmentation.dva`
3. Writes a result JSON to `C:\Users\Docker\customer_value_segmentation_result.json`

The `verify_customer_value_segmentation()` function:
1. Copies the result JSON from the VM
2. Checks file existence and `is_new` flag (mtime > task_start)
3. Copies the DVA file from the VM
4. Decompresses `.arc` entries using `zlib.decompress()` (canvas/column names live here)
5. Searches combined text for exact canvas names and column identifiers (case-insensitive)

## Data Schema Reference

**File:** `sample_order_lines2023.xlsx` (Global retail orders — international markets including cities in Europe, Middle East, Asia, Americas; ~9000 rows)

| Column | Type | Notes |
|--------|------|-------|
| Customer Segment | string | Consumer, Corporate, Home Office |
| Customer Name | string | Individual customer names |
| City | string | International cities (Paris, Riyadh, Ahmedabad, Dortmund, etc.) |
| Sales | numeric | Revenue per order line |
| Profit | numeric | Net profit per order line |
| Shipping Cost | numeric | Shipping cost per order line |
| Discount | numeric | Discount fraction (0.0–1.0) |
| Quantity Ordered | integer | Units ordered |
| Product Category | string | Office Supplies, Furniture, Technology |
| Product Container | string | Jumbo Box, Large Box, Medium Box, Small Box, Wrap Bag |
| Ship Mode | string | Express Air, Regular Air, Delivery Truck |
| Order Priority | string | Critical, High, Medium, Low, Not Specified |

## Data Diversity Note

This task uses `sample_order_lines2023.xlsx` (global market data) rather than `order_lines.csv` (US Superstore data). The datasets share the same schema but contain entirely different order records from different geographic markets, providing data diversity across the benchmark tasks.

## Edge Cases

- DVA files are ZIP archives containing `.arc` files (zlib-compressed). Canvas names and calculated column identifiers are in `.arc` entries — plain JSON search misses them.
- The workbook must be saved AFTER the task start timestamp. Pre-existing workbooks are cleaned up by `setup_task.ps1`.
- The Excel file must be loaded as a dataset in OAD (File > Add Dataset, select the .xlsx file).
- The export script scans `Documents\`, `Desktop\`, and the home directory for the DVA file.
