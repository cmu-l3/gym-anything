# Motor Selection Parametric Sweep

## Overview
A university rocketry team needs to select the optimal motor for a 3048m (10,000 ft) target altitude. The base rocket design has no motor configurations or simulations. The agent must create multiple flight configurations with different motors, run simulations for each, export comparison data to CSV, and write a motor selection report.

## Domain Context
Motor selection is a fundamental task in rocket design. Engineers test multiple motors across different impulse classes to find the optimal balance of altitude performance, cost, and availability. A proper parametric sweep requires testing at least 4 distinct motors across 7+ configurations.

## Source Data
- **Base rocket**: `simple_model_rocket.ork` — a clean single-motor rocket design
- **Setup**: All existing simulations and motor configs are cleared; agent starts from scratch

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Parametric sweep | 50 | >=7 uptodate sims with >=4 distinct motor designations |
| CSV export | 20 | Motor comparison CSV with altitude/motor data |
| Selection report | 15 | Report with motor recommendation |
| Target altitude | 15 | Best sim within 30% of 3048m target |
| **Pass threshold** | **60** | |

## Anti-Gaming
- >=7 sims with <4 distinct motors scores 0 for the sweep criterion (not a valid parametric sweep)
- Do-nothing max score is 0 (no sims, no CSV, no report exist)

## Verification Strategy
Verifier builds a configid→designation map from the rocket's motormount elements, then cross-references with simulation conditions to count distinct motors. CSV and report are checked via copy_from_env.
