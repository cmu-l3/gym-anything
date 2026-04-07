# Flight Data Export and Analysis

## Overview
A clustered-motor rocket with 5 motor configurations (A8, B4, C6-3s, C6-5s, C6-7s) has outdated simulations and no data exports. The agent must re-run all simulations, export time-series flight data as CSV files, and write a comprehensive performance comparison report recommending the optimal motor for a 250m target altitude.

## Domain Context
Propulsion engineers routinely compare motor configurations by running simulations and analyzing the resulting flight data. This task requires using OpenRocket's simulation, data export, and analysis features — a multi-step workflow combining several application capabilities.

## Source Data
- **Base rocket**: `clustered_motors.ork` — real rocket design with 5 motor configurations
- **Motor configs**: A8 (~58m), B4 (~142m), C6-3s (~279m), C6-5s (~307m), C6-7s (~307m)
- **Setup**: All simulations reset to 'outdated', flight data removed

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Simulations run | 30 | >=4 of 5 sims have 'uptodate' status |
| CSV exports | 30 | >=3 CSV files in exports/flight_data/ |
| Performance metrics | 15 | Report contains altitude/velocity data for multiple configs |
| Best config identified | 10 | Report identifies the highest-performing configuration |
| Target recommendation | 15 | Report recommends motor for 250m target |
| **Pass threshold** | **65** | Sims+CSVs alone = 60 (below threshold), report required |

## Verification Strategy
Verifier parses `.ork` for simulation status, probes multiple possible CSV filenames via copy_from_env, and checks report content with regex for metrics, best config, and recommendation keywords.
