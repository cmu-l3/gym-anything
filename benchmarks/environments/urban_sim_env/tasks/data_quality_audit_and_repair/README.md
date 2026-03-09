# Task: Data Quality Audit and Repair

## Domain Context

**Role**: Urban Data Quality Analyst, San Francisco Planning Department GIS Unit
**Industry**: Urban Planning / Government / Data Engineering
**Software**: Jupyter Lab, Python (pandas), UrbanSim framework
**Occupation grounding**: Urban and Regional Planners (O*NET importance: 77/100)

Real-world land use datasets frequently contain data quality issues that compound over time through system migrations, manual entry errors, and batch import failures. Before running any microsimulation or planning analysis, analysts must audit, document, and repair these issues. This task reproduces a data quality lifecycle: audit → categorize → repair → document.

---

## Goal

Audit the file `/home/ga/urbansim_projects/data/buildings_with_errors.csv` for data quality issues. This file contains the San Francisco buildings dataset with real errors injected across multiple categories. You must:

1. **Discover** what categories of errors exist (they are not named or described to you)
2. **Document** each error category in a structured quality report
3. **Repair** the records where possible
4. **Produce** a cleaned dataset and summary visualization

The error discovery is the hardest part — you must recognize anomalous patterns in the data using domain knowledge of what reasonable building attributes look like.

---

## Input File

```
/home/ga/urbansim_projects/data/buildings_with_errors.csv
```

This file was constructed from `sanfran_public.h5` buildings table with deliberate errors injected (details unknown to the agent — must be discovered through analysis).

Reference data (for comparison and repair): `/home/ga/urbansim_projects/data/sanfran_public.h5`

---

## Required Outputs

| File | Location | Description |
|------|----------|-------------|
| `quality_report.csv` | `/home/ga/urbansim_projects/output/` | One row per error category discovered |
| `buildings_repaired.csv` | `/home/ga/urbansim_projects/output/` | Cleaned buildings dataset |
| `data_quality_chart.png` | `/home/ga/urbansim_projects/output/` | Chart summarizing error counts by category |
| Executed notebook | `/home/ga/urbansim_projects/notebooks/data_quality_audit.ipynb` | All cells run |

### quality_report.csv Required Columns

| Column | Description |
|--------|-------------|
| `issue_type` | Name or label for the error category (agent's choice) |
| `records_affected` | Count of records with this error |
| `repair_method` | Description of how the error was repaired |
| `records_repaired` | Count of records actually repaired |

---

## Difficulty

**Level**: very_hard

This task is hard because:
- The agent is NOT told what errors exist or how many categories there are
- The agent must apply domain knowledge to recognize implausible building attributes
- Four distinct error categories are present, requiring broad data exploration
- The quality report format requires the agent to categorize errors meaningfully
- Both a report AND a repaired dataset must be produced

---

## Error Categories (Ground Truth — Known to Verifier, Not to Agent)

The setup script injects exactly four error categories using `np.random.seed(42)`:

| Category | Description | Count |
|----------|-------------|-------|
| Physical impossibility | Buildings with >15 stories but `building_sqft < 3000` | 55 |
| Temporal anomaly | `year_built` set to future years (2050, 2075, 2099) | 38 |
| Missing price | Residential buildings (`residential_units > 0`) with `residential_sales_price = 0` | 110 |
| Density anomaly | Buildings with >800 units but <5 stories | 28 |
| **Total** | | **231** |

The verifier uses flexible keyword matching for `issue_type` — the agent may label categories in any reasonable way (e.g., "impossible_height", "physical_anomaly", or "stories_sqft_mismatch" all match the physical category).

---

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| `quality_report.csv` has ≥3 issue types and required columns | 20 | Structure check |
| Each GT error category detected (7 pts each, +2 for all 4) | 30 | Flexible keyword matching |
| `buildings_repaired.csv` exists, is new, has ≥80% of original rows | 20 | Repair output check |
| Chart exists, is new, >5 KB | 15 | File check |
| Notebook has ≥6 executed cells | 15 | Execution count |

**Pass threshold**: 60/100

---

## Verification Strategy

The `export_result.sh` script:
1. Reads `quality_report.csv` and checks `issue_type` column values against keyword sets
2. Counts lines in `buildings_repaired.csv` (without loading the full file)
3. Validates chart existence and freshness
4. Counts executed notebook cells

Keyword matching sets used for error category detection:
- **Physical**: `['physical', 'sqft', 'footprint', 'stories', 'building_sqft', 'impossible_height']`
- **Temporal**: `['year', 'temporal', 'date', 'built', 'future', 'historic']`
- **Price**: `['price', 'sale', 'value', 'zero_price', 'missing_price']`
- **Density**: `['density', 'unit', 'residential_unit', 'capacity']`

---

## Anti-Gaming Notes

- The agent is not told the error categories — it must discover them through data exploration
- The ground truth counts (55, 38, 110, 28) are not in the task description — the verifier checks if the agent detected the right *categories*, not exact counts
- `buildings_repaired.csv` row count must be ≥80% of original (prevents trivially deleting all records)
