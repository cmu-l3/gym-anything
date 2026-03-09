# Task: Zone Job Accessibility Equity Analysis

## Domain Context

**Role**: Transportation Equity Analyst, Metropolitan Transportation Commission (MTC)
**Industry**: Regional Transportation / Government / Equity Research
**Software**: UrbanSim framework, Jupyter Lab, Python (pandas, geopandas)
**Occupation grounding**: Urban and Regional Planners (O*NET importance: 77/100)

California SB 375 requires Metropolitan Planning Organizations to demonstrate that their transportation plans reduce vehicle miles traveled and advance equity for low-income and disadvantaged communities. MTC's equity mandate requires identifying which zones have the worst job accessibility for low-income households — zones where residents must travel the farthest to reach jobs relative to their transportation options.

This task reproduces a standard Equity Assessment required for regional plan compliance: computing a zone-level equity gap score that captures how unevenly jobs are distributed relative to where low-income households live.

---

## Goal

Compute a job accessibility equity analysis for all San Francisco zones that have both households and jobs. The analysis must:

1. Join job locations to their zones via the buildings → parcels → zone chain
2. Identify low-income households using the 30th percentile of the SF household income distribution
3. Compute a zone-level equity gap score that captures the disparity between job access and low-income household presence
4. Produce a visualization of the 15 worst-equity zones

The specific equity gap formula is the analyst's professional judgment. The task tests whether the agent can perform the multi-table join, apply the income threshold, and construct a meaningful composite metric — not whether a specific formula is used.

---

## Required Outputs

| File | Location | Description |
|------|----------|-------------|
| `zone_accessibility.csv` | `/home/ga/urbansim_projects/output/` | One row per zone |
| `equity_chart.png` | `/home/ga/urbansim_projects/output/` | Bar chart of 15 worst-equity zones |
| Executed notebook | `/home/ga/urbansim_projects/notebooks/zone_equity.ipynb` | All cells run |

### zone_accessibility.csv Required Columns

| Column | Description |
|--------|-------------|
| `zone_id` | Zone identifier |
| `total_jobs` | Total jobs located in the zone |
| `total_households` | Total households in the zone |
| `low_income_households` | Households with income ≤ 30th percentile of SF distribution |
| `low_income_share` | Fraction of households that are low-income (0 to 1) |
| `jobs_per_household` | Ratio of total jobs to total households |
| `equity_gap_score` | Composite equity gap metric (must be normalized to [0, 1]) |

---

## Data

```
/home/ga/urbansim_projects/data/sanfran_public.h5
```

| Table | Key Columns |
|-------|-------------|
| `jobs` | `building_id` (FK to buildings) |
| `buildings` | `parcel_id` (FK to parcels) |
| `parcels` | `zone_id` |
| `households` | `building_id`, `income` |

**Required join chain for jobs**:
```
jobs.building_id → buildings.index → buildings.parcel_id → parcels.index → parcels.zone_id
```

**Low-income threshold**: 30th percentile of `households.income` across all SF households.

---

## Difficulty

**Level**: very_hard

This task is hard because:
- The 4-table join chain is non-trivial and requires understanding the UrbanSim schema
- The agent must define "low-income" using an income percentile (not given a threshold)
- The equity gap score formula must be designed by the agent
- The score must be normalized to [0,1] — unnormalized scores fail verification
- Both zone-level statistics AND a visual deliverable are required
- The chart must correctly rank and display the 15 worst zones

---

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| CSV exists, is new, has required columns, ≥30 zones | 20 | Structure + coverage |
| `equity_gap_score` in [0,1], values vary (std > 0) | 20 | Score validity |
| `low_income_share` in [0,1]; `jobs_per_household` ≥ 0 | 20 | Column plausibility |
| Chart exists, is new, >5 KB | 25 | File check |
| Notebook has ≥3 executed cells | 15 | Execution count |

**Pass threshold**: 60/100

---

## Verification Strategy

The `export_result.sh` script:
1. Reads `zone_accessibility.csv` using inline Python and checks all required columns
2. Validates `equity_gap_score` range and standard deviation
3. Validates `low_income_share` range and `jobs_per_household` non-negativity
4. Checks chart existence, freshness (mtime > task_start_ts), and size
5. Counts executed notebook cells

The `verifier.py` function `verify_zone_job_equity` applies multi-criterion scoring.

---

## Ground Truth (Computed at Setup Time)

The setup script stores in `/tmp/zone_equity_gt.json`:
- `income_p30`: 30th percentile of SF household income (defines "low-income")
- `total_households`, `total_jobs`
- `zones_with_households`, `zones_with_jobs`
- `median_jobs_per_zone`

---

## Anti-Gaming Notes

- `equity_gap_score` must vary across zones (std > 0 check) — prevents all-same scores
- `equity_gap_score` must be in [0,1] — raw unscaled values fail
- Jobs join requires the full 4-table chain — no shortcut to zone-level data
- File freshness check prevents reuse of stale files from prior runs
