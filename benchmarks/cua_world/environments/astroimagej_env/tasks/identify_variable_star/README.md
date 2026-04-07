# Task: Identify Variable Star in WASP-12 Field

## Overview
Variable star identification from time-series CCD observations is a core astronomy workflow. Given a field of stars, the astronomer must perform differential photometry on multiple candidates simultaneously, compare their light curves, and determine which star shows genuine variability versus instrumental noise.

This task uses **real astronomical data** from the University of Louisville AstroImageJ examples: 186 calibrated r-band CCD frames of the WASP-12 stellar field, taken with the MORC24 telescope.

## Data Source
- **Target field**: WASP-12 (RA 06:30:32.79, Dec +29:40:20.4)
- **Instrument**: MORC24 telescope, University of Louisville
- **Filter**: r-band
- **Images**: 186 calibrated 4096x4096 FITS frames
- **Exposure**: 100 seconds per frame
- **Data URL**: https://www.astro.louisville.edu/software/astroimagej/examples/WASP-12b_example_calibrated_images.tar.gz

## Goal
Discover which star in the WASP-12 field is variable using multi-aperture differential photometry across 186 frames. The agent is NOT told which star is variable -- they must figure it out by analyzing the light curves.

## Scientific Context
WASP-12 is the host star of WASP-12b, a well-known "hot Jupiter" exoplanet discovered in 2008. The planet orbits extremely close to its star (orbital period 1.09 days) and causes a ~1.4% transit dip when it passes in front of the star. This is a subtle signal that requires careful differential photometry to detect -- the other bright comparison stars in the field remain constant.

## Starting State
- AstroImageJ is launched with 186 FITS images loaded as a virtual stack from ~/AstroImages/variable_search/
- The first image is displayed
- No apertures or analysis have been set up

## Agent Workflow
1. Place apertures on at least 5 bright stars in the field (including WASP-12 and comparison stars)
2. Run multi-aperture photometry across all 186 frames
3. Examine the resulting light curves to identify which star shows variability
4. Create a report file (variable_star_report.txt) with findings

## Success Criteria (100 points, pass threshold 60)
1. **Measurement table** (25 pts): Multi-star photometry data saved with >=100 rows and >=3 stars
2. **Variable star identified** (25 pts): Report correctly names WASP-12 or T1 as the variable
3. **Transit depth** (20 pts): Approximate depth reported as ~1.4% (tolerance: +/-0.5%)
4. **Transit timing** (15 pts): Frame numbers or JD of minimum brightness reported
5. **Report file** (15 pts): Complete report with star identification, depth, and timing

## Key Difference from detect_exoplanet_transit Task
Both tasks use the same WASP-12b dataset, but with fundamentally different objectives:
- **detect_exoplanet_transit**: The agent is TOLD that WASP-12 is the target and must characterize the transit (depth, duration, planet radius)
- **identify_variable_star**: The agent must DISCOVER which star is variable by comparing light curves of multiple candidates

## Verification
- Measurement file checked for sufficient data and multi-star coverage
- Report file parsed for variable star identification (WASP-12 / T1 name match)
- Transit depth compared to expected value (1.4% +/- 0.5%)
- Timing information validated against observation sequence range
