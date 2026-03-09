# Task: Building Market Segmentation

## Domain Context

**Role**: Real Estate Data Analyst, San Francisco Assessor's Office
**Industry**: Government / Real Estate Assessment
**Software**: UrbanSim framework, scikit-learn, Jupyter Lab, Python
**Occupation grounding**: Urban and Regional Planners (O*NET importance: 77/100)

The Assessor's Office uses spatial and market data to categorize the residential building stock for tax assessment review, capital improvement planning, and AHBP (Affordable Housing Bonus Program) targeting. This task reproduces a standard market segmentation analysis where buildings are grouped into tiers based on revealed price signals.

---

## Goal

Perform k-means clustering to segment San Francisco's residential building stock into **exactly 3 market tiers** based on price and physical characteristics. The three clusters should represent meaningfully distinct market segments (e.g., affordable, mid-market, premium) — not arbitrary groupings.

The clustering methodology, feature selection, and scaling are left to the analyst. The only hard constraints are:
- Exactly 3 clusters
- The most expensive cluster must have a mean price-per-sqft at least 1.5× the cheapest cluster
- Only residential buildings with valid price data are eligible (filter before clustering)

---

## Required Outputs

| File | Location | Description |
|------|----------|-------------|
| `building_clusters.csv` | `/home/ga/urbansim_projects/output/` | One row per eligible building with cluster assignment |
| `cluster_profiles.csv` | `/home/ga/urbansim_projects/output/` | Exactly 3 rows: one per cluster, with aggregated statistics |
| `market_segmentation_chart.png` | `/home/ga/urbansim_projects/output/` | Scatter plot of clusters (e.g., price vs. age, color-coded by cluster) |
| Executed notebook | `/home/ga/urbansim_projects/notebooks/building_segmentation.ipynb` | All cells run |

### building_clusters.csv Required Columns

| Column | Description |
|--------|-------------|
| `building_id` | Building identifier |
| `cluster_id` | Cluster assignment (0, 1, or 2) |
| `price_per_sqft` | Residential sales price per square foot |

### cluster_profiles.csv Required Columns

| Column | Description |
|--------|-------------|
| `cluster_id` | Cluster identifier |
| `mean_price_per_sqft` | Mean price per sqft for this cluster |
| `building_count` | Number of buildings in cluster |
| Any additional profile statistics (optional) | e.g., `mean_year_built`, `mean_stories` |

---

## Data

```
/home/ga/urbansim_projects/data/sanfran_public.h5
```

| Table | Key Columns |
|-------|-------------|
| `buildings` | `building_sqft`, `residential_units`, `year_built`, `stories`, `residential_sales_price`, `non_residential_sqft` |

**Eligibility filter** (agent must determine appropriate filters):
- `residential_units > 0`
- `building_sqft > 0`
- `residential_sales_price > 0`

---

## Difficulty

**Level**: very_hard

This task is hard because:
- The agent must select clustering features and decide on scaling/normalization
- Exactly 3 clusters is a constraint, not a suggestion — the agent must use `n_clusters=3`
- The 1.5× price ratio gate means random cluster assignments fail verification
- The agent must produce both building-level and cluster-level outputs (two different CSV formats)
- No example code or clustering workflow is provided

---

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| `building_clusters.csv` exists, is new, ≥500 rows, has required columns | 20 | File + structure |
| Exactly 3 distinct cluster IDs; row count plausible | 25 | Cluster count validation |
| `cluster_profiles.csv` has exactly 3 rows; price ratio ≥1.5 | 25 | Profiles validation |
| Chart exists, is new, >10 KB | 20 | File check |
| Notebook has ≥4 executed cells | 10 | Execution count |

**Pass threshold**: 60/100

---

## Verification Strategy

The `export_result.sh` script uses inline Python to:
1. Load `building_clusters.csv` and check unique cluster IDs (must be exactly 3)
2. Load `cluster_profiles.csv` and compute max/min `mean_price_per_sqft` ratio
3. Check chart file freshness and size
4. Count executed notebook cells

The `verifier.py` function `verify_building_segmentation` applies multi-criterion scoring based on the exported JSON.

---

## Ground Truth (Computed at Setup Time)

The setup script stores in `/tmp/building_market_segmentation_gt.json`:
- `eligible_building_count`: Number of buildings passing all filters
- `price_p25`, `price_p50`, `price_p75`: Price percentiles for context
- `year_built_min`, `year_built_max`: Year range

The 1.5× price ratio threshold is intrinsic — any meaningful 3-cluster segmentation of SF residential prices will exceed this ratio.

---

## Anti-Gaming Notes

- Exactly-3-cluster gate prevents trivial 1-cluster or all-same solutions
- Price ratio ≥1.5 prevents assigning all buildings to nearly identical clusters
- File freshness (`mtime > task_start_ts`) prevents reuse of stale files
- Minimum ≥500 rows in building_clusters.csv ensures substantial coverage
