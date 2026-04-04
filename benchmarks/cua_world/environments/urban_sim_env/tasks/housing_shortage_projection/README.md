# Task: Housing Shortage Projection

## Domain Context

**Role**: Urban Economist, San Francisco Controller's Office
**Industry**: Government / Urban Economics / Housing Policy
**Software**: UrbanSim / orca microsimulation framework, Jupyter Lab, Python
**Occupation grounding**: Urban and Regional Planners (O*NET importance: 77/100)

Housing shortage quantification is a core deliverable for city economists advising on zoning reform, infrastructure bonding, and state housing law compliance (SB 9, SB 10, SB 330). The standard approach uses microsimulation to track household formation against new unit supply. This task requires using the orca framework — the engine underlying UrbanSim — to run a multi-year simulation that produces year-by-year deficit estimates.

---

## Goal

Build and run a 5-year orca-based simulation (2020–2024) that estimates the annual housing shortage in San Francisco. The simulation must model household growth against new housing unit production to compute a running deficit.

The orca framework (`import orca`) must be used. The simulation must use `@orca.step()` decorator to define simulation steps and `orca.run(iter_vars=[2020, 2021, 2022, 2023, 2024])` to execute 5 iterations.

The specific growth rates, household formation models, and construction models are the economist's design — the task tests whether the agent can build a functioning orca simulation and produce a structured deficit projection, not whether the projection matches a specific value.

---

## Required Outputs

| File | Location | Description |
|------|----------|-------------|
| `housing_shortage.csv` | `/home/ga/urbansim_projects/output/` | Exactly 5 rows: one per year 2020–2024 |
| `housing_shortage_chart.png` | `/home/ga/urbansim_projects/output/` | Line chart of annual vs. cumulative deficit over time |
| Executed notebook | `/home/ga/urbansim_projects/notebooks/housing_shortage.ipynb` | All cells run, orca simulation executed |

### housing_shortage.csv Required Columns

| Column | Description |
|--------|-------------|
| `year` | Simulation year (2020, 2021, 2022, 2023, 2024) |
| A column for households at start of year | e.g., `households_start` |
| A column for new households added | e.g., `new_households` |
| A column for new units built | e.g., `new_units` |
| A column for annual deficit | e.g., `annual_deficit` (new_households - new_units) |
| A column for cumulative deficit | e.g., `cumulative_deficit` |

---

## Data

```
/home/ga/urbansim_projects/data/sanfran_public.h5
```

Key baseline statistics (for starting state):

| Table | Key Info |
|-------|----------|
| `households` | Starting household count for 2020 |
| `buildings` | Total residential capacity |
| `parcels` | Parcel count for development potential |
| `zoning` | Max density constraints |

---

## Difficulty

**Level**: very_hard

This task is hard because:
- The agent must learn and use the `orca` framework, which is not standard Python
- `@orca.step()` decorator pattern must be correctly implemented
- `orca.run(iter_vars=[...])` requires understanding the iter_vars paradigm
- The agent must design a plausible household growth and unit production model
- Two distinct outputs are required (CSV + chart)
- Deficit values must vary across years (constant = incomplete model)

---

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| CSV columns present (year + households + units + deficit) | 20 | Column name matching |
| Exactly 5 rows, correct year sequence 2020–2024 | 25 | Row count + year values |
| Deficits non-zero, vary across years, plausible values | 25 | Simulation quality |
| `import orca`, `@orca.step`, `orca.run(` in notebook | 10 | Framework usage verification |
| Chart exists, is new, >5 KB | 10 | File check |
| Notebook has ≥4 executed cells | 10 | Execution count |

**Pass threshold**: 60/100

---

## Verification Strategy

The `export_result.sh` script:
1. Reads `housing_shortage.csv` and extracts year values and deficit columns
2. Searches notebook source for `import orca`, `orca.run(`, and `@orca.step` or `orca.step`
3. Validates deficit values are non-zero and within plausible range (< 1,000,000)
4. Checks chart existence and freshness

The `verifier.py` function `verify_housing_shortage` applies multi-criterion scoring.

---

## Ground Truth (Computed at Setup Time)

The setup script computes and stores in `/tmp/housing_shortage_gt.json`:
- `total_households_2020`: Starting household count (baseline)
- `total_buildings`: Number of residential buildings
- `total_parcels`: Number of parcels (development context)
- `avg_residential_density`: Mean units per building (for calibrating growth model)
- `has_zoning_table`: Whether the zoning table is accessible

These are provided as context metadata, not as values the agent must reproduce.

---

## Anti-Gaming Notes

- The verifier checks orca framework usage in the notebook source code (not just output)
- Deficit values must vary across years — a constant deficit implies no simulation was run
- Plausibility check: deficits must be < 1,000,000 (prevents obviously synthetic large numbers)
- Year sequence must be exactly [2020, 2021, 2022, 2023, 2024] (5 rows with correct values)
