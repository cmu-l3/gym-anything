# sales_trend_quarterly_analysis

## Domain Context

**Occupation**: Business Intelligence Analyst (SOC 15-2051.01)
**Industry**: Retail / Sales Analytics
**Application**: Azure Data Studio + Microsoft SQL Server 2022 (AdventureWorks2022)

A BI analyst supporting the sales leadership team needs to identify quarter-over-quarter growth trends and rank salespersons within their territories. Leadership wants to know who is consistently growing their quarterly revenue and who the top performers are by territory so bonuses and territory realignments can be planned.

---

## Task Goal

Build a sales trend analytics view in `AdventureWorks2022` and export a summary report. The deliverables are:

1. A view (`dbo.vw_SalesPersonQuarterlyTrend`) that aggregates quarterly sales per salesperson and territory, applies a LAG window function to derive quarter-over-quarter growth, and ranks salespersons within their territory using DENSE_RANK
2. A CSV file at `/home/ga/Documents/exports/top_sales_trends.csv` containing the top 5 salespersons by average quarter-over-quarter growth (excluding quarters with no prior quarter data)

The view must pull from the `Sales` schema tables and the CSV must reflect the current database values.

---

## Expected End State

- `dbo.vw_SalesPersonQuarterlyTrend` view exists in `AdventureWorks2022`
- View has >= 50 rows of quarterly sales data
- View includes columns for: salesperson identity, territory, calendar year and quarter, quarterly sales, previous quarter's sales (via LAG), QoQ growth percentage, and sales rank within territory and year
- `PrevQuarterSales` column has non-zero values (LAG function is working)
- `SalesRankInTerritory` starts at 1 (DENSE_RANK is correct)
- CSV exists at `/home/ga/Documents/exports/top_sales_trends.csv`
- CSV has exactly 5 data rows
- CSV salesperson names match the database's top 5 by average QoQ growth

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| View dbo.vw_SalesPersonQuarterlyTrend exists | 15 |
| View has all 10 required columns | 20 |
| View has >= 50 rows | 10 |
| PrevQuarterSales has non-zero values (LAG working) | 10 |
| SalesRankInTerritory minimum is 1 | 5 |
| CSV file exists at correct path | 15 |
| CSV has exactly 5 data rows | 10 |
| CSV top-5 names match DB query (>= 3/5) | 15 |
| **Pass threshold** | **70/100** |

---

## Verification Strategy

`export_result.sh` checks:
- `sys.views` — view existence
- `INFORMATION_SCHEMA.COLUMNS` — column count (checks for 8+ of 10 required columns)
- `COUNT(*)` — row count
- `COUNT(*) WHERE PrevQuarterSales <> 0` — LAG is working
- `MIN(SalesRankInTerritory)` — DENSE_RANK starts at 1
- File existence and line count of CSV
- Cross-validation: top 5 FirstNames by AVG(QoQGrowthPct) from DB vs CSV content

All results written to `/tmp/sales_trend_result.json`.

---

## Required View Columns

| Column | Type | Source |
|--------|------|--------|
| SalesPersonID | INT | Sales.SalesPerson.BusinessEntityID |
| FirstName | NVARCHAR | Person.Person |
| LastName | NVARCHAR | Person.Person |
| TerritoryName | NVARCHAR | Sales.SalesTerritory |
| CalendarYear | INT | Sales.SalesOrderHeader via date functions |
| CalendarQuarter | INT | DATEPART(QUARTER, ...) |
| QuarterlySales | DECIMAL | SUM(SubTotal) grouped by person/territory/year/quarter |
| PrevQuarterSales | DECIMAL | LAG(QuarterlySales) OVER (PARTITION BY SalesPersonID ORDER BY CalendarYear, CalendarQuarter) |
| QoQGrowthPct | DECIMAL | (QuarterlySales - PrevQuarterSales) / PrevQuarterSales * 100 |
| SalesRankInTerritory | INT | DENSE_RANK() OVER (PARTITION BY TerritoryName, CalendarYear ORDER BY QuarterlySales DESC) |

---

## Source Data

| Table | Key Columns | Usage |
|-------|------------|-------|
| `Sales.SalesOrderHeader` | SalesPersonID, TerritoryID, SubTotal, OrderDate | Sales amounts and dates |
| `Sales.SalesPerson` | BusinessEntityID, TerritoryID | Salesperson-territory mapping |
| `Sales.SalesTerritory` | TerritoryID, Name | Territory names |
| `Person.Person` | BusinessEntityID, FirstName, LastName | Salesperson names |

---

## Edge Cases

- First quarter for each salesperson has no prior quarter → `PrevQuarterSales IS NULL`; these rows should be excluded from the CSV top-5 calculation
- Multiple salespersons in same territory on same quarter → DENSE_RANK assigns same rank for ties
- CSV must have a header row + exactly 5 data rows
- `/home/ga/Documents/exports/` directory must be created if it doesn't exist

---

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task specification, metadata, hooks |
| `setup_task.sh` | Drops existing view, removes old CSV, opens ADS |
| `export_result.sh` | Queries view and CSV, writes `/tmp/sales_trend_result.json` |
| `verifier.py` | Reads JSON, applies multi-criterion scoring, returns pass/fail |
