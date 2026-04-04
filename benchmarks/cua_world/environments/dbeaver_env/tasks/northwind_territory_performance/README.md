# Task: Northwind Territory Performance Analysis

## Domain
Business Intelligence — Sales Territory Analysis

## Occupation Context
**Business Intelligence Analysts** (GDP impact: $2.6B) use SQL tools like DBeaver to query
multi-table databases, aggregate sales by geographic regions, and produce executive-level
performance reports. This task reflects the real BI workflow of connecting to an operational
database, writing complex JOIN queries with aggregation, and exporting results for stakeholders.

## Goal
Analyze territory-level sales performance from the Northwind business database by:
1. Connecting to the Northwind SQLite database in DBeaver
2. Writing a complex multi-table JOIN query spanning Orders, OrderDetails, Products,
   Territories, EmployeeTerritories, and Region
3. Computing per-territory: revenue, order count, average order value, employee headcount
4. Exporting the result to a specific CSV path
5. Saving the SQL query as a script file

## Database: Northwind
- **Location**: `/home/ga/Documents/databases/northwind.db`
- **Source**: Northwind Traders — classic business sample database (Microsoft/jpwhite3)
- **Tables used**: Orders, OrderDetails, Products, Territories, EmployeeTerritories, Region, Employees

### Key Relationships
```
Employees ──< EmployeeTerritories >── Territories ──> Region
Orders ──────── via EmployeeID ─────> Employees
Orders ──────< OrderDetails >──── Products
```

### Revenue Formula
`Revenue = SUM(Quantity * UnitPrice * (1 - Discount))` across all OrderDetails for all
Orders attributed to employees in a territory.

## Expected Deliverables

### 1. DBeaver Connection
- Name: `Northwind` (exact, case-sensitive)
- Driver: SQLite
- Path: `/home/ga/Documents/databases/northwind.db`

### 2. Output CSV: `/home/ga/Documents/exports/territory_report.csv`
Required columns:
- `TerritoryID` — territory identifier
- `TerritoryDescription` — territory name
- `RegionDescription` — region name (Eastern, Western, Northern, Southern)
- `TotalRevenue` — summed revenue for all orders in this territory
- `OrderCount` — distinct number of orders
- `AvgOrderValue` — TotalRevenue / OrderCount
- `EmployeeCount` — distinct employees assigned to this territory

Sorted by TotalRevenue descending.

### 3. SQL Script: `/home/ga/Documents/scripts/territory_analysis.sql`
The query used to produce the CSV. Any valid SQL approach is accepted.

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| DBeaver 'Northwind' connection exists | 15 | data-sources.json parsed |
| territory_report.csv exists at exact path | 15 | file existence + size |
| CSV has all 7 required columns | 20 | header parsing |
| CSV row count between 40-60 | 15 | line count |
| Top territory revenue within 10% of ground truth | 20 | value comparison |
| SQL script saved at exact path | 15 | file existence |

**Pass threshold: 60 points**

## Difficulty Factors
- Must discover the ER diagram / schema independently
- Requires 4+ table JOIN (not a single-table query)
- Revenue formula involves the Discount column (easy to miss)
- Territory-to-order mapping is non-obvious (via EmployeeTerritories → Employees → Orders)
- Must produce exact output path and column structure

## Schema Reference (for verifier)
```sql
-- Tables in Northwind SQLite (jpwhite3 version)
CREATE TABLE Territories (TerritoryID TEXT, TerritoryDescription TEXT, RegionID INTEGER)
CREATE TABLE Region (RegionID INTEGER, RegionDescription TEXT)
CREATE TABLE EmployeeTerritories (EmployeeID INTEGER, TerritoryID TEXT)
CREATE TABLE Employees (EmployeeID INTEGER, LastName TEXT, FirstName TEXT, ...)
CREATE TABLE Orders (OrderID INTEGER, CustomerID TEXT, EmployeeID INTEGER, OrderDate TEXT, ...)
CREATE TABLE OrderDetails (OrderID INTEGER, ProductID INTEGER, UnitPrice REAL, Quantity INTEGER, Discount REAL)
```
