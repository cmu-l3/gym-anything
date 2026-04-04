# Task: channel_improvement_comparison

## Overview
**Occupation:** Environmental Engineer (O*NET 17-2081.00)
**Industry:** Environmental Consulting / Urban Planning / River Restoration
**Difficulty:** very_hard
**Environment:** HEC-RAS 6.6 (Linux, command-line) + Python/h5py

## Scenario
An environmental engineer at an urban planning and water resources consulting firm must prepare a benefit analysis for the City of Muncie's White River Restoration Project as part of an Indiana State Revolving Fund (SRF) grant application. The project proposes channel improvements that reduce Manning's roughness by 25% in the main channel. The engineer must run two HEC-RAS simulations (baseline and improved), compare results, and produce a technical recommendation on whether the project meets the 0.3 ft WSE-reduction design criterion.

## Real Data Sources
- **Hydraulic Model:** USACE HEC-RAS 6.6 Muncie example — White River, Muncie, Indiana
- **Manning's n:** Values read directly from the HDF5 template file geometry data
- **Reference Program:** Indiana Clean Water Indiana Program (IDEM Office of Water Quality), modeled on real SRF grant requirements

## What the Agent Must Do
1. Read `~/Documents/channel_improvement_spec.txt` (improved n = 25% reduction, main-channel cells only)
2. Run BASELINE simulation → extract peak WSE, mean WSE, inundated cell count → save to `baseline_results.json`
3. Modify Manning's n in `Muncie.p04.tmp.hdf` using Python/h5py (lowest tercile cells only)
4. Run IMPROVED simulation → extract same metrics → save to `improved_results.json`
5. Write `~/Documents/hec_ras_results/scenario_comparison.csv` (2 rows, 6 columns including flood_reduction_pct)
6. Write `~/Documents/hec_ras_results/project_benefit_summary.txt` (≥5 sentences + design criterion assessment)

## Why This is Hard
- Must run TWO complete simulation workflows and manage results separately
- Must correctly identify main-channel cells via elevation percentile analysis (lowest tercile)
- Must modify only a subset of Manning's n cells (not all cells)
- Must compute flood_reduction_pct correctly
- Must integrate quantitative results into a coherent engineering recommendation

## Verification (GT-in-Setup Pattern)
- Setup pre-computes baseline and improved simulation GT results
- Verifier checks: baseline WSE within ±0.5 ft of GT, improved WSE correctly lower, CSV structure, summary content
- Score cap at 50 if only baseline completed (both scenarios required)
- Pass threshold: 60/100 points
