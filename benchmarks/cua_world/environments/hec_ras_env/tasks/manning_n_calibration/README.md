# Task: manning_n_calibration

## Overview
**Occupation:** Senior Hydrologist (O*NET 19-2043.00)
**Industry:** Government / Environmental Science / Water Resources
**Difficulty:** very_hard
**Environment:** HEC-RAS 6.6 (Linux, command-line) + Python/h5py

## Scenario
A senior hydrologist at the Indiana Department of Natural Resources must calibrate the HEC-RAS White River model to reproduce a peak stage observed at a USGS gauge during a recent storm event. The model's Manning's roughness coefficient has been set to an incorrect value, and the hydrologist must conduct a systematic sensitivity study to find the value that minimizes the residual between simulated and observed peak WSE.

## Real Data Sources
- **Calibration Target:** Derived from the USACE HEC-RAS 6.6 Muncie example model's own default simulation (real USGS gauge 03349000 record)
- **Manning's n Storage:** HDF5 dataset `Geometry/2D Flow Areas/Muncie/Manning's n` in Muncie.p04.tmp.hdf

## What the Agent Must Do
1. Read observed peak WSE from `~/Documents/observed_gauge_data.txt`
2. Use Python/h5py to read and modify Manning's n in `Muncie.p04.tmp.hdf`
3. Run at least 3 simulations with different n values (iterative calibration)
4. Log all runs to `~/Documents/hec_ras_results/calibration_log.csv`
5. Apply the best-fit n to the HDF5 template as the final calibrated model
6. Write `~/Documents/hec_ras_results/calibration_report.txt` with key metrics

## Why This is Hard
- Must understand the HDF5 structure of the HEC-RAS template file
- Must implement iterative calibration (not a single-step task)
- Must manage file state between multiple runs
- Must apply scientific reasoning to converge on the correct n value
- The starting n value is deliberately wrong (20% too high)

## Verification (GT-in-Setup Pattern)
- Setup runs baseline simulation, records true peak WSE as "observed" target
- Perturbs Manning's n upward by 20% as the wrong starting point
- Verifier checks: number of iterations, final n value vs. true value, best simulated WSE vs. target
- Pass threshold: 60/100 points
