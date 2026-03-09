# Task: Aperture Photometry on HST WFPC2 Image (`measure_star_photometry@1`)

## Overview
Aperture photometry — measuring a star's brightness by summing pixel values within a circular aperture — is the most fundamental photometric operation in astronomy. This task uses a real Hubble Space Telescope WFPC2 image and requires the agent to open the FITS file, identify a star, perform aperture photometry using AstroImageJ's tools, and produce measurement results.

## Data Source
- **Telescope**: NASA/ESA Hubble Space Telescope
- **Instrument**: Wide Field and Planetary Camera 2 (WFPC2)
- **Image**: hst_wfpc2_sample.fits (pre-installed sample from ESA)

## Goal
Open a FITS image in AstroImageJ and perform aperture photometry on a bright star, producing a measurements table with flux values.

## Starting State
- AstroImageJ is launched but NO image is loaded — the agent must open the FITS file themselves
- FITS file available at: ~/AstroImages/raw/hst_wfpc2_sample.fits
- Measurements output directory: ~/AstroImages/measurements/

## Agent Workflow
1. Open the FITS file (File > Open or Ctrl+O)
2. Identify a bright star in the field
3. Use aperture photometry (Analyze > Aperture Photometry > Multi-Aperture, or click on a star)
4. Measurements appear in a Results window

## Success Criteria (percentage-based, pass at 70%)
1. **AIJ image loaded** — FITS file opened in AstroImageJ
2. **Measurements recorded** — At least one photometry measurement exists
3. **FITS window visible** — wmctrl detects an open FITS image window
4. **Results window visible** — A Results/Measurements table window is present
5. **FITS interaction evidence** — Positive evidence the agent interacted with the file
6. **VLM process verification** — Trajectory frames show workflow progression
7. **VLM content quality** — Final frame shows genuine photometry work
8. **VLM error check** — No crashes or error dialogs

## Verification
Hybrid programmatic + VLM. Programmatic checks query AstroImageJ state via macro and wmctrl window detection. VLM checks use trajectory frames to verify the agent progressed through FITS loading, aperture placement, and results display.
