# Task: flood_frequency_analysis

## Overview
**Occupation:** Civil Engineer / Hydraulic Engineer (O*NET 17-2051.00)
**Industry:** Government / Water Resources / FEMA Flood Insurance Studies
**Difficulty:** very_hard
**Environment:** HEC-RAS 6.6 (Linux, command-line)

## Scenario
A hydraulic engineer at a regional flood control district must perform a flood frequency analysis for the White River at Muncie, Indiana as part of a FEMA Flood Insurance Study (FIS) update. Using USGS peak-flow frequency estimates for USGS Gauge 03349000, the engineer must simulate three design flood events (10-year, 50-year, 100-year), extract peak water surface elevations, and document the Base Flood Elevation (BFE).

## Real Data Sources
- **USGS Gauge:** 03349000 — White River at Muncie, Indiana
- **Frequency Method:** USGS Bulletin 17C Log-Pearson Type III
- **Design Flows:** Q₁₀ = 16,200 cfs, Q₅₀ = 23,100 cfs, Q₁₀₀ = 26,200 cfs
- **Model:** USACE HEC-RAS 6.6 Muncie example project

## What the Agent Must Do
1. Read USGS frequency report at `~/Documents/usgs_white_river_frequency.txt`
2. For each return period, scale the hydrograph in `Muncie.b04` proportionally
3. Run `RasUnsteady` simulation for each return period
4. Extract peak WSE from `Muncie.p04.hdf` using Python/h5py
5. Write `~/Documents/hec_ras_results/frequency_results.csv` (3 rows, correct columns)
6. Write `~/Documents/hec_ras_results/bfe_documentation.txt` with `BFE=<value>`

## Why This is Hard
- Agent must parse the b04 hydrograph format and implement proportional scaling
- Must run 3 separate simulations without overwriting results
- Must interface with HDF5 output files using Python
- Must maintain correct file management across multiple runs
- Must understand the FEMA BFE concept and correctly identify it

## Verification
- `frequency_results.csv`: 3 rows, correct return periods, matching design flows, plausible monotonically-increasing WSE values
- `bfe_documentation.txt`: BFE= line consistent with 100-yr simulation output
- Pass threshold: 60/100 points
