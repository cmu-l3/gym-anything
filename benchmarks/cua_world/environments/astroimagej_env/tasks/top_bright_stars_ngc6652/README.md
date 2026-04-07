# Task: Identify and Measure the Five Brightest Stars in NGC 6652 (`top_bright_stars_ngc6652@1`)

## Overview

Identifying and precisely measuring the brightest stars in a crowded stellar field is a fundamental observational astronomy skill that requires careful source selection, aperture placement in crowded conditions, and systematic recording of results. This task uses a real Hubble Space Telescope WFPC2 image of the dense globular cluster NGC 6652, where the agent must locate the five brightest resolved stars, perform aperture photometry on each, and compile a ranked catalog with pixel positions and integrated flux values.

## Rationale

**Why this task is valuable:**
- Tests star identification and selection in a crowded field (not just an isolated star)
- Requires iterative aperture photometry on multiple specific targets
- Evaluates the agent's ability to compile and organize measurement results
- Exercises spatial reasoning to distinguish individual stars in a dense cluster core
- Verifiable against ground truth derived from the real HST data

**Real-world Context:** An astronomer has obtained a deep image of globular cluster NGC 6652 and needs to create a preliminary bright-star catalog for follow-up spectroscopy. The telescope scheduling committee needs the five brightest targets with their positions and relative brightnesses to plan slit placements.

## Data Source

- **Telescope**: NASA/ESA Hubble Space Telescope
- **Instrument**: Wide Field and Planetary Camera 2 (WFPC2)
- **Filter**: F814W (I-band, ~814 nm)
- **Target**: NGC 6652, a moderately concentrated globular cluster in Sagittarius
- **Plate scale**: ~0.1 arcsec/pixel (WFPC2 WF chips)
- **Origin**: ESA Hubble FITS Liberator datasets, pre-installed at `/opt/fits_samples/ngc6652/`

## Goal

Open the NGC 6652 F814W FITS image in AstroImageJ, visually identify the five brightest stars in the field, perform aperture photometry on each, and save a ranked catalog file containing their pixel coordinates (x, y) and integrated source flux values, ordered from brightest to faintest.

## Starting State

- AstroImageJ is launched and the NGC 6652 F814W image is loaded and displayed
- The image is displayed with default contrast settings
- No apertures, measurements, or analysis have been set up
- The file `~/AstroImages/ngc6652_project/ngc6652_814w.fits` contains the image
- The output file should be saved to: `~/AstroImages/ngc6652_project/bright_star_catalog.txt`

## Expected Agent Workflow

1. **Examine the image**: Adjust brightness/contrast if needed to distinguish individual bright stars in the crowded cluster field
2. **Identify the 5 brightest stars**: Visually scan the field and identify the five stars with the highest peak pixel values or apparent brightness
3. **Perform aperture photometry on each star**: Place an aperture on each of the 5 brightest stars and record the integrated flux (source counts minus background)
4. **Record pixel coordinates**: Note the centroid x,y pixel position of each measured star
5. **Compile the catalog**: Create the file `~/AstroImages/ngc6652_project/bright_star_catalog.txt` with format: