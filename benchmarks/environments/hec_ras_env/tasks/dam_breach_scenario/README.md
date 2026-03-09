# Task: dam_breach_scenario

## Overview
**Occupation:** Civil Engineer / Dam Safety Engineer (O*NET 17-2051.00)
**Industry:** Government / Dam Safety / Emergency Engineering
**Difficulty:** very_hard
**Environment:** HEC-RAS 6.6 (Linux, command-line) + Python/h5py

## Scenario
A dam safety engineer at the Indiana Dam Safety Program must simulate a hypothetical upstream dam failure scenario using HEC-RAS. Using Froehlich (1995) peak outflow equation parameters for a hypothetical earthen dam, the engineer must construct a triangular dam-break hydrograph, modify the model's boundary conditions, run the simulation, and produce an emergency inundation report for downstream communities near Muncie.

## Real Data Sources
- **Breach Method:** Froehlich, D.C. (1995). Peak Outflow from Breached Embankment Dam. J. Water Resour. Plng. and Mgmt., ASCE, 121(1), 90-97.
- **Scenario:** Hypothetical 42-ft earthen dam, 8,400 acre-ft reservoir — typical small Midwestern reservoir
- **Background Model:** USACE HEC-RAS 6.6 Muncie example, White River, Muncie Indiana

## What the Agent Must Do
1. Read dam breach parameters from `~/Documents/dam_breach_parameters.txt`
2. Construct a triangular hydrograph (peak=45,000 cfs, Tp=2 hr, base=12 hr) with 1-hour intervals
3. Replace the existing upstream boundary hydrograph in `Muncie.b04` with the dam-break hydrograph
4. Run `RasUnsteady Muncie.p04.tmp.hdf x04`
5. Extract peak WSE, mean peak WSE, and peak timestep from `Muncie.p04.hdf`
6. Write `~/Documents/hec_ras_results/dam_breach_report.txt` with labeled metrics + narrative

## Why This is Hard
- Must correctly parse and understand the HEC-RAS b04 hydrograph format
- Must construct a dam-break hydrograph from physical parameters (hours → minutes conversion)
- The peak flow (45,000 cfs) is 2× the standard flood — must handle this correctly
- Must extract specific HDF5 results after the larger-peak simulation
- Must write a technically accurate narrative report

## Verification
- b04 must be modified (wrong-target gate)
- Peak flow in b04 must be 45,000 cfs ±10%
- Simulation must be run
- Peak WSE must be > 953.84 ft (above standard-event baseline)
- Pass threshold: 60/100 points
