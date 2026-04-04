# vendor_performance_analytics

## Domain Context

**Occupation**: Logistics Analyst (SOC 13-1081.02)
**Industry**: Manufacturing / Supply Chain Management
**Application**: Azure Data Studio + Microsoft SQL Server 2022 (AdventureWorks2022)

A logistics analyst at a manufacturing company is responsible for measuring vendor reliability and cost efficiency. Management needs a quarterly vendor scorecard that combines order volume, cost variance (comparing invoiced unit prices to standard cost), and on-time delivery rates — all aggregated per vendor and ranked so underperforming vendors can be identified for review.

---

## Task Goal

Build a vendor performance analytics system in the `AdventureWorks2022` database. The deliverable is:

1. A new schema (`Analytics`) and a summary table (`Analytics.VendorPerformance`) that stores aggregated performance metrics per vendor
2. A stored procedure (`dbo.usp_VendorPerformanceReport`) that accepts a date range and populates the summary table with one row per vendor, including metrics for order volume, line items, cost variance, on-time delivery rate, and a performance rank
3. After creating the procedure, execute it for the date range `'2013-01-01'` to `'2014-01-01'`

The table must be populated with actual data from the `Purchasing` schema when the task is complete.

---

## Expected End State

- `Analytics` schema exists in `AdventureWorks2022`
- `Analytics.VendorPerformance` table exists with at least 5 columns capturing vendor identity, order counts, cost variance, delivery rate, and rank
- `dbo.usp_VendorPerformanceReport` stored procedure exists
- `Analytics.VendorPerformance` is populated (>= 5 rows) after executing the procedure
- Vendor rank column uses DENSE_RANK() so ranks start at 1 and are sequential
- OnTimeDeliveryRate (or equivalent) is a decimal/float between 0 and 1
- Vendor names in the table match vendors in `Purchasing.Vendor`

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Analytics schema exists | 10 |
| VendorPerformance table exists | 15 |
| Stored procedure exists | 20 |
| Table has 7 required columns | 15 |
| Table has >= 5 rows of data | 15 |
| Rank column uses sequential DENSE_RANK (min=1, max=distinct ranks) | 10 |
| Delivery rate column values in [0.0, 1.0] | 10 |
| Vendor names cross-validate against Purchasing.Vendor | 5 |
| **Pass threshold** | **70/100** |

---

## Verification Strategy

`export_result.sh` queries:
- `sys.schemas` — Analytics schema existence
- `sys.objects` (type='U') — VendorPerformance table existence
- `sys.procedures` — stored procedure existence
- `INFORMATION_SCHEMA.COLUMNS` — column count and names
- `MIN/MAX/COUNT(DISTINCT VendorRank)` — sequential rank validation
- `SELECT COUNT(*) WHERE OnTimeDeliveryRate NOT BETWEEN 0 AND 1` — rate range check
- Cross-validate top 3 VendorNames against `Purchasing.Vendor`

All results written to `/tmp/vendor_perf_result.json`.

`verifier.py` reads this JSON and applies the scoring matrix above.

---

## Source Data

All data comes from the AdventureWorks2022 `Purchasing` schema:

| Table | Key Columns | Usage |
|-------|------------|-------|
| `Purchasing.Vendor` | BusinessEntityID, Name | Vendor identity and names |
| `Purchasing.PurchaseOrderHeader` | VendorID, OrderDate, ShipDate | Order volume and delivery timing |
| `Purchasing.PurchaseOrderDetail` | UnitPrice, ReceivedQty, LineTotal | Line item quantities and costs |
| `Production.Product` | StandardCost | Benchmark unit cost for variance |

AdventureWorks2022 ships with real historical purchasing data spanning 2001–2014.

---

## Edge Cases

- Some vendors may have no orders in the specified date range → procedure should handle gracefully (no rows for those vendors)
- DENSE_RANK should partition or order by a performance metric so ties get the same rank
- OnTimeDeliveryRate is `NULL` if ShipDate is NULL; handle with COALESCE or WHERE filter
- The `Analytics` schema must be created before the table
- The stored procedure must be dropped and recreated if it already exists (use `DROP/CREATE` or `CREATE OR ALTER`)

---

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task specification, metadata, hooks |
| `setup_task.sh` | Drops any pre-existing Analytics schema/table/proc, opens ADS |
| `export_result.sh` | Queries all verification criteria, writes `/tmp/vendor_perf_result.json` |
| `verifier.py` | Reads JSON, applies multi-criterion scoring, returns pass/fail |
