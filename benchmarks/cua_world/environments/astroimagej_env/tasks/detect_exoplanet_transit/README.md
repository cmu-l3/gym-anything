# Task: Detect Exoplanet Transit in WASP-12 Observations (`detect_exoplanet_transit@1`)

## Overview
Exoplanet transit detection from time-series differential photometry is one of the most impactful observational astronomy workflows. This task requires the agent to analyze a full night of CCD observations, perform multi-aperture differential photometry, identify a transit signal in the resulting light curve, and measure the transit parameters.

## Data Source
- **Target**: WASP-12 (RA 06:30:32.79, Dec +29:40:20.4), host of hot Jupiter WASP-12b
- **Instrument**: MORC24 telescope, University of Louisville
- **Filter**: r-band
- **Images**: ~186 calibrated 4096x4096 FITS frames, 100s exposures
- **Data URL**: https://www.astro.louisville.edu/software/astroimagej/examples/WASP-12b_example_calibrated_images.tar.gz

## Goal
Determine whether the time-series photometry of WASP-12 shows evidence of a planetary transit. If so, measure the transit depth, mid-transit time, transit duration, and estimate the planet radius.

## Starting State
- AstroImageJ is launched with the WASP-12b calibrated images loaded as a virtual stack
- The first image is displayed
- No apertures or analysis have been set up

## Agent Workflow
1. Identify WASP-12 in the field using provided coordinates
2. Select at least 2 comparison stars for differential photometry
3. Configure aperture settings and run multi-aperture photometry across all frames
4. Examine the resulting light curve for a transit dip
5. Measure transit depth (%), mid-transit time (BJD_TDB), and duration (hours)
6. Calculate planet radius assuming host star radius = 1.599 solar radii

## Success Criteria (100 points, pass threshold 60)
1. **Measurement file** (25 pts): Photometry table with >=100 data points, time and flux columns
2. **Differential photometry** (12 pts): At least 2 comparison stars used
3. **Transit depth** (15 pts): ~1.4% +/- 0.3%
4. **Transit duration** (10 pts): ~2.7h +/- 1.0h
5. **Mid-transit time** (3 pts): Reported in BJD
6. **Planet radius** (5 pts): ~1.79 R_J +/- 0.5 R_J
7. **VLM process verification** (15 pts): Trajectory shows workflow progression
8. **VLM light curve content** (10 pts): Valid light curve with transit dip visible
9. **Cross-validation** (5 pts): Programmatic depth agrees with VLM transit detection

## Verification
Hybrid programmatic + VLM. Export script captures photometry results from the container. VLM checks use framework-captured trajectory frames to verify the agent progressed through image loading, aperture setup, photometry execution, and light curve analysis.
