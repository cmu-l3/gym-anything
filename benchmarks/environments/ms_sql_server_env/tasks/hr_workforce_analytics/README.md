# hr_workforce_analytics

## Domain Context

**Occupation**: HR Analytics Manager (SOC 11-3121.00)
**Industry**: Human Resources / Workforce Management
**Application**: Azure Data Studio + Microsoft SQL Server 2022 (AdventureWorks2022)

An HR analytics manager has been asked by the CHRO to deliver a workforce dashboard before the board meeting. The dashboard needs headcount, compensation benchmarks, gender representation, and tenure statistics broken down by department. This data is spread across multiple HumanResources tables and must be consolidated into a single summary table that can be refreshed on demand.

---

## Task Goal

Build a workforce analytics system in `AdventureWorks2022`. The deliverables are:

1. A table (`HumanResources.WorkforceSummary`) that stores one row per department with aggregated workforce metrics: active headcount, average/min/max hourly pay rate, female and male counts, average tenure in days, and count of senior employees (>= 10 years)
2. A stored procedure (`HumanResources.usp_RefreshWorkforceSummary`) that truncates and repopulates the summary table by joining the four key HumanResources tables, using ROW_NUMBER() to get the most recent pay rate per employee, and using conditional aggregation for gender counts
3. A non-clustered index on `HumanResources.WorkforceSummary(DepartmentID)` for performance
4. After creating all objects, execute the stored procedure to populate the table

---

## Expected End State

- `HumanResources.WorkforceSummary` table exists in `AdventureWorks2022`
- Table has at least 8 columns covering: department ID, department name, active employee count, average hourly rate, female count, male count, average tenure days, senior employee count
- `HumanResources.usp_RefreshWorkforceSummary` stored procedure exists
- Table is populated with one row per active department (>= 8 rows from AdventureWorks data)
- `FemaleCount + MaleCount = ActiveEmployeeCount` for all rows (conditional aggregation is correct)
- `AvgHourlyRate > 0` for all rows (pay history join is working)
- Department names match `HumanResources.Department`
- Non-clustered index on `DepartmentID` exists

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| HumanResources.WorkforceSummary table exists | 20 |
| Table has 8 required columns | 20 |
| Table populated with >= 8 department rows | 20 |
| HumanResources.usp_RefreshWorkforceSummary stored procedure exists | 15 |
| FemaleCount + MaleCount = ActiveEmployeeCount (conditional aggregation correct) | 10 |
| AvgHourlyRate > 0 (pay history ROW_NUMBER join working) | 5 |
| Department names cross-validate against HumanResources.Department | 5 |
| Non-clustered index on DepartmentID exists | 5 |
| **Pass threshold** | **70/100** |

---

## Verification Strategy

`export_result.sh` checks:
- `sys.objects` (type='U') — table existence
- `INFORMATION_SCHEMA.COLUMNS` — column names and count
- `COUNT(*) FROM HumanResources.WorkforceSummary` — row count
- `sys.procedures JOIN sys.schemas` — stored procedure existence
- `COUNT(*) WHERE (FemaleCount + MaleCount) = ActiveEmployeeCount` — gender arithmetic
- `COUNT(*) WHERE AvgHourlyRate > 0` — pay rate validity
- Top 3 DepartmentNames cross-validated against `HumanResources.Department`
- `sys.indexes JOIN sys.index_columns` — non-clustered index on DepartmentID

All results written to `/tmp/hr_workforce_result.json`.

---

## Required Table Columns

| Column | Type | Source |
|--------|------|--------|
| SummaryID | INT IDENTITY PK | Auto-generated |
| DepartmentID | SMALLINT | HumanResources.Department |
| DepartmentName | NVARCHAR(50) | HumanResources.Department.Name |
| GroupName | NVARCHAR(50) | HumanResources.Department.GroupName |
| ActiveEmployeeCount | INT | COUNT(*) from EmployeeDepartmentHistory WHERE EndDate IS NULL |
| AvgHourlyRate | DECIMAL(10,4) | AVG of most recent Rate per employee (via ROW_NUMBER) |
| MaxHourlyRate | DECIMAL(10,4) | MAX Rate |
| MinHourlyRate | DECIMAL(10,4) | MIN Rate |
| FemaleCount | INT | SUM(CASE WHEN Gender='F' THEN 1 ELSE 0 END) |
| MaleCount | INT | SUM(CASE WHEN Gender='M' THEN 1 ELSE 0 END) |
| AvgTenureDays | INT | AVG(DATEDIFF(DAY, HireDate, GETDATE())) |
| SeniorEmployeeCount | INT | SUM(CASE WHEN DATEDIFF(DAY, HireDate, GETDATE()) >= 3650 THEN 1 ELSE 0 END) |
| ReportGeneratedAt | DATETIME | GETDATE() on insert |

---

## Source Data

| Table | Key Columns | Usage |
|-------|------------|-------|
| `HumanResources.Department` | DepartmentID, Name, GroupName | Department identity |
| `HumanResources.EmployeeDepartmentHistory` | BusinessEntityID, DepartmentID, EndDate | Current department assignments (EndDate IS NULL = active) |
| `HumanResources.Employee` | BusinessEntityID, Gender, HireDate | Demographics and hire date |
| `HumanResources.EmployeePayHistory` | BusinessEntityID, Rate, RateChangeDate | Pay rates (multiple records per employee; use ROW_NUMBER to get latest) |

---

## Key Implementation Details

The pay rate deduplication must use a window function:
```sql
WITH LatestPay AS (
    SELECT BusinessEntityID, Rate,
           ROW_NUMBER() OVER (PARTITION BY BusinessEntityID ORDER BY RateChangeDate DESC) AS rn
    FROM HumanResources.EmployeePayHistory
)
SELECT ... FROM LatestPay WHERE rn = 1
```

This is required because each employee may have multiple pay history records; using `MAX(Rate)` would give the highest rate, not the most recent.

---

## Edge Cases

- Departments with no active employees should be excluded (use HAVING COUNT > 0)
- `SeniorEmployeeCount` tenure threshold: 3650 days ≈ 10 years (365 × 10)
- The stored procedure should be in the `HumanResources` schema, not `dbo`
- Use `TRUNCATE TABLE` + `INSERT` (not `UPDATE`) for idempotency

---

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task specification, metadata, hooks |
| `setup_task.sh` | Drops existing table/proc, opens ADS |
| `export_result.sh` | Queries all verification criteria, writes `/tmp/hr_workforce_result.json` |
| `verifier.py` | Reads JSON, applies multi-criterion scoring, returns pass/fail |
