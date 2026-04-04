# Task: Measure Double Star in HST NGC 6652 Image

## Overview
Double star measurement is a classical observational astronomy task. This task uses
real Hubble Space Telescope data of the globular cluster NGC 6652, where the dense
stellar field provides many close star pairs suitable for astrometric measurement.

## Data Source
- **Telescope**: NASA/ESA Hubble Space Telescope
- **Instrument**: Wide Field and Planetary Camera 2 (WFPC2)
- **Filter**: F555W (V-band, ~555 nm)
- **Target**: NGC 6652 globular cluster
- **Plate scale**: 0.1 arcsec/pixel (WFPC2 Wide Field chips)
- **Origin**: ESA Hubble FITS Liberator datasets

The FITS file is downloaded during environment installation from the ESA Hubble
archive and cached at `/opt/fits_samples/ngc6652/`.

## Goal
Locate a marked close star pair in the NGC 6652 field and measure:
1. Angular separation in arcseconds
2. Position angle (PA) of the fainter component relative to the brighter, measured North through East
3. Magnitude difference between the two components via aperture photometry

## Starting State
- `~/AstroImages/double_star/ngc6652_555w.fits` -- real HST WFPC2 V-band image
- `~/AstroImages/double_star/target_pair.txt` -- approximate pixel coordinates of the target pair
- AstroImageJ is launched and ready
- FITS header contains `PLATESCL = 0.1` keyword and comments about the plate scale

## Ground Truth
Ground truth values are **measured from the real data** during task setup (not hardcoded).
The setup script:
1. Detects bright sources via thresholding and centroiding
2. Identifies a close pair with 15-40 pixel separation and moderate brightness contrast
3. Computes separation, PA, and magnitude difference from the centroid positions and aperture fluxes
4. Saves ground truth to `/tmp/double_star_ground_truth.json` (not visible to agent)

## Success Criteria (100 points, pass at 60)
1. **Results file created** (15 pts) -- `double_star_results.txt` with labeled measurements
2. **Separation within tolerance** (25 pts) -- compared to ground truth from real data
3. **Position angle within tolerance** (25 pts) -- PA measured N through E
4. **Magnitude difference within tolerance** (20 pts) -- from aperture photometry
5. **Photometric measurement evidence** (15 pts) -- AstroImageJ measurement/CSV files present

## Notes
- No synthetic data is used; all measurements come from the actual HST observation
- The globular cluster field is crowded, so careful identification of the marked pair is needed
- The WFPC2 WF chip plate scale of 0.1 arcsec/pixel is much finer than typical ground-based imaging
