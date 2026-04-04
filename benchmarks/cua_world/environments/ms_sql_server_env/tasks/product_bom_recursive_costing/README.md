# product_bom_recursive_costing

## Domain Context

**Occupation**: Cost Engineer / Industrial Engineer (SOC 17-2112.00)
**Industry**: Manufacturing / Product Lifecycle Management
**Application**: Azure Data Studio + Microsoft SQL Server 2022 (AdventureWorks2022)

A cost engineer at a manufacturing company is responsible for computing total material costs for assembled products. To price products accurately, the full bill of materials (BOM) must be traversed recursively — a bike's components have sub-components, which have sub-sub-components — and the cost at every level must be accounted for. The engineer needs a system that automates this multi-level BOM traversal and produces a cost report per assembly.

---

## Task Goal

Build a recursive BOM cost analysis system in `AdventureWorks2022`. The deliverables are:

1. A view (`dbo.vw_ProductBOMHierarchy`) using a recursive CTE that traverses `Production.BillOfMaterials` to expose the full component hierarchy (assembly → component → sub-component → ...) with level depth, component names, and quantity per assembly
2. A table (`Production.LifecycleCostSummary`) that stores one row per assembly with aggregated cost metrics: total component count, maximum BOM depth, direct material cost (level 1 only), and full BOM cost (all levels)
3. A stored procedure (`dbo.usp_GenerateBOMCostReport`) that truncates and repopulates `Production.LifecycleCostSummary` by querying the recursive view and joining `Production.Product` for standard costs
4. A non-clustered index on `Production.LifecycleCostSummary` to support queries by assembly product ID
5. After creating all objects, execute the stored procedure to populate the summary table

---

## Expected End State

- `dbo.vw_ProductBOMHierarchy` exists in `AdventureWorks2022`
- View uses a recursive CTE anchored on `Production.BillOfMaterials WHERE ProductAssemblyID IS NOT NULL`
- View has columns for assembly ID, assembly name, component ID, component name, BOM level, quantity per assembly, and unit of measure
- View contains rows at BOMLevel > 1 (recursion is working, not just direct children)
- `Production.LifecycleCostSummary` table exists with columns for assembly ID, assembly name, total component count, max BOM depth, direct material cost, full BOM cost, and report timestamp
- Non-clustered index on `Production.LifecycleCostSummary(AssemblyProductID)` exists
- `dbo.usp_GenerateBOMCostReport` stored procedure exists
- `Production.LifecycleCostSummary` is populated with at least 5 rows of real cost data after executing the procedure
- `TotalMaterialCost` values are > 0 (cost calculation is correct)

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| dbo.vw_ProductBOMHierarchy view exists | 15 |
| View has 7 required columns | 15 |
| View has >= 10 rows with BOMLevel > 1 (recursion works) | 15 |
| Production.LifecycleCostSummary table exists | 10 |
| Table has 6+ required columns | 10 |
| Table populated with >= 5 rows and TotalMaterialCost > 0 | 15 |
| Non-clustered index on AssemblyProductID exists | 5 |
| dbo.usp_GenerateBOMCostReport stored procedure exists | 15 |
| **Pass threshold** | **70/100** |

---

## Verification Strategy

`export_result.sh` checks:
- `sys.views` — view existence
- `INFORMATION_SCHEMA.COLUMNS` — view column count
- `COUNT(*) WHERE BOMLevel > 1` — recursive CTE is working
- `sys.objects` (type='U') — table existence
- `INFORMATION_SCHEMA.COLUMNS` — table column count
- `COUNT(*) FROM Production.LifecycleCostSummary WHERE TotalMaterialCost > 0` — cost data populated
- `sys.indexes JOIN sys.index_columns` — non-clustered index on AssemblyProductID
- `sys.procedures` — stored procedure existence

All results written to `/tmp/bom_cost_result.json`.

---

## Required View Columns

| Column | Type | Source |
|--------|------|--------|
| AssemblyProductID | INT | Root of each BOM tree (recursive anchor) |
| AssemblyName | NVARCHAR | Production.Product.Name for assembly |
| ComponentID | INT | Production.BillOfMaterials.ComponentID |
| ComponentName | NVARCHAR | Production.Product.Name for component |
| BOMLevel | INT | Depth counter (1 = direct child, 2 = grandchild, ...) |
| PerAssemblyQty | DECIMAL | Production.BillOfMaterials.PerAssemblyQty |
| UnitMeasureCode | NCHAR | Production.BillOfMaterials.UnitMeasureCode |

---

## Source Data

| Table | Key Columns | Usage |
|-------|------------|-------|
| `Production.BillOfMaterials` | ProductAssemblyID, ComponentID, BOMLevel, PerAssemblyQty, UnitMeasureCode, EndDate | BOM hierarchy |
| `Production.Product` | ProductID, Name, StandardCost | Product names and standard costs |

Only active BOM rows should be used: `EndDate IS NULL`.

AdventureWorks2022 has multi-level BOM data for assembled products (bicycles and their components), making recursive traversal genuinely multi-level.

---

## Edge Cases

- Recursive CTEs require an anchor member (base case) and a recursive member; the anchor should be rows where `ProductAssemblyID IS NOT NULL`
- Some assemblies have only 1-2 levels; the view should handle variable depth without infinite recursion (SQL Server limits with `MAXRECURSION`)
- `StandardCost` may be 0 for some components; `TotalMaterialCost` will be 0 for those assemblies
- The stored procedure should use `TRUNCATE TABLE` before `INSERT` for idempotency
- The view must be created before the stored procedure that queries it

---

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task specification, metadata, hooks |
| `setup_task.sh` | Drops existing view/table/proc, opens ADS |
| `export_result.sh` | Queries all verification criteria, writes `/tmp/bom_cost_result.json` |
| `verifier.py` | Reads JSON, applies multi-criterion scoring, returns pass/fail |
