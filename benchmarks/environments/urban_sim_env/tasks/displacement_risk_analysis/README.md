# Task: Displacement Risk Analysis

## Domain Context

**Role**: Housing Policy Analyst, San Francisco Planning Department
**Industry**: Urban Planning / Government
**Software**: UrbanSim microsimulation framework, Jupyter Lab, Python
**Occupation grounding**: Urban and Regional Planners (O*NET importance: 77/100)

Residential displacement is one of San Francisco's most urgent policy challenges. This task simulates a real deliverable requested by the Mayor's Office: a zone-level Displacement Risk Index (DRI) to guide the allocation of the city's anti-displacement investment fund. The analyst must combine multiple data signals into a composite index, a standard technique in equity-focused planning.

---

## Goal

Build a Displacement Risk Index for every San Francisco zone that has both residential households and buildings. The DRI must combine three independent components:

1. **Vulnerability** — concentration of low-income households who cannot relocate easily
2. **Precarity** — age and quality of the building stock (older buildings are prime redevelopment targets)
3. **Development pressure** — how close buildings are to maximum zoning density (indicating speculator interest)

The methodology — how you define "low-income," how you weight the components, how you normalize — is the analyst's professional judgment. The task tests analytical reasoning, not mechanical reproduction of a formula.

---

## Required Outputs

| File | Location | Description |
|------|----------|-------------|
| `displacement_risk.csv` | `/home/ga/urbansim_projects/output/` | One row per zone with all index components |
| `displacement_risk_chart.png` | `/home/ga/urbansim_projects/output/` | Horizontal bar chart of 20 highest-DRI zones |
| Executed notebook | `/home/ga/urbansim_projects/notebooks/displacement_risk.ipynb` | All cells run, outputs visible |

### CSV Required Columns

| Column | Description |
|--------|-------------|
| `zone_id` | Zone identifier (integer) |
| `dri_score` | Final composite Displacement Risk Index, normalized to [0, 1] |
| `vulnerability_score` | Component score for household vulnerability |
| `precarity_score` | Component score for building stock precarity |
| `pressure_score` | Component score for development pressure |
| `low_income_households` | Count of households below income threshold |
| `total_households` | Total households in zone |
| `mean_price_per_sqft` | Mean residential sales price per square foot |

---

## Data

All data comes from the San Francisco UrbanSim dataset:

```
/home/ga/urbansim_projects/data/sanfran_public.h5
```

| Table | Key Columns |
|-------|-------------|
| `buildings` | `parcel_id`, `building_sqft`, `residential_units`, `year_built`, `stories`, `residential_sales_price` |
| `households` | `building_id`, `income` |
| `parcels` | `zone_id` |
| `zoning` | `max_far` (maximum floor-area ratio) |

**Join chain**: households → buildings (via `building_id`) → parcels (via `parcel_id`) → `zone_id`

**Note**: `residential_sales_price` is synthetically generated from census data (this is documented in the dataset), but is the best available price signal for this analysis.

---

## Difficulty

**Level**: very_hard

This task is hard because:
- The agent must design the methodology (no formula given)
- Three independent components must be computed and combined
- Multi-table joins are required across 4 tables
- Normalization to [0,1] must be applied thoughtfully
- The chart requires sorting and selecting top zones

---

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| CSV exists, is new, ≥50 rows | 20 | File freshness + row count |
| 5 required columns present | 20 | Column name validation (flexible matching) |
| DRI scores in [0,1] with std > 0.01 | 20 | Anti-trivial-solution check |
| Supplementary columns present | 15 | `low_income_households`, `mean_price_per_sqft` |
| Chart exists, is new, >10 KB | 15 | File check |
| Notebook has ≥3 executed cells | 10 | Cell execution count |

**Pass threshold**: 60/100

---

## Verification Strategy

The `export_result.sh` script:
1. Reads `displacement_risk.csv` using inline Python and checks column presence
2. Validates `dri_score` range and standard deviation (std > 0 → not all identical)
3. Checks chart file existence, freshness (mtime > task_start_ts), and size
4. Counts executed notebook cells

The `verifier.py` function `verify_displacement_risk`:
- Copies `/tmp/displacement_risk_result.json` from VM
- Applies multi-criterion scoring
- Returns `{"passed": bool, "score": int, "feedback": str}`

---

## Ground Truth (Computed at Setup Time)

The setup script pre-computes and stores in `/tmp/displacement_risk_gt.json`:
- `income_p25`: 25th percentile of household income (reference for "low-income" definition)
- `zones_with_data`: Number of zones with ≥10 households
- `total_households`, `total_buildings`

---

## Anti-Gaming Notes

- Files deleted before `task_start_ts` is recorded → freshness checks are valid
- DRI std > 0.01 check prevents trivially identical scores
- Minimum 50 zones prevents single-zone or tiny outputs
