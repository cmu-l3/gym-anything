# Task: CCD Image Calibration Pipeline (Real Palomar LFC Data)

## Overview

Standard CCD calibration is the most fundamental data reduction step in observational
astronomy. Every raw CCD frame contains instrumental artifacts (bias offset, dark current,
pixel-to-pixel sensitivity variations) that must be removed before any scientific analysis.
This task requires the agent to execute the complete calibration pipeline in AstroImageJ
using **real observational data** from a professional telescope.

## Data Source

**Palomar 200-inch Hale Telescope, Large Format Camera (LFC)**

The data comes from the Astropy CCD Reduction Guide dataset, publicly available on Zenodo
(DOI: 10.5281/zenodo.3254683). These are real cryo-cooled CCD frames taken with the
Large Format Camera on the Palomar 200-inch (5.1-meter) Hale Telescope at Palomar
Observatory, California.

The dataset includes bias, dark, flat-field, and science (light) frames categorized by the
standard FITS `IMAGETYP` header keyword. Frame counts and image dimensions depend on the
specific dataset contents; ground truth statistics are computed from the actual data at
task setup time rather than being hardcoded.

## Goal

Produce calibrated science frames from raw CCD data by creating and applying master
calibration frames (bias, dark, flat) using the standard CCD reduction pipeline.

## Starting State

- `~/AstroImages/calibration_project/` contains organized subdirectories:
  - `bias/` -- Bias frames (IMAGETYP=BIAS, zero-second exposures)
  - `dark/` -- Dark frames (IMAGETYP=DARK, matched exposure time)
  - `flat/` -- Flat-field frames (IMAGETYP=FLAT, twilight or dome flats)
  - `science/` -- Science frames (IMAGETYP=LIGHT/OBJECT, target observations)
  - `reduced/` -- Empty output directory for calibrated products
- AstroImageJ is launched and ready

## Calibration Pipeline Steps

1. **Master Bias**: Median-combine all bias frames to create a low-noise bias template
2. **Master Dark**: Median-combine dark frames, then subtract the master bias to isolate
   thermal signal
3. **Master Flat**: Median-combine flat frames, subtract the master bias, then normalize
   by dividing by the median pixel value (so the result has mean near 1.0)
4. **Calibrate Science**: For each science frame, subtract the master bias and scaled
   master dark, then divide by the normalized master flat

## Success Criteria

1. Master bias exists in `reduced/` directory (median of bias frames) -- 20 pts
2. Master dark exists and is bias-subtracted -- 20 pts
3. Master flat exists and is normalized (mean near 1.0) -- 20 pts
4. Calibrated science frames exist in `reduced/` -- 25 pts
5. Calibrated frames have pixel values significantly different from raw -- 15 pts

Pass threshold: 70/100 points

## Verification

Ground truth statistics are computed from the real Palomar LFC data during task setup
and saved to `/tmp/calibration_ground_truth.json`. The verifier reads this file to
determine expected values for the master bias mean, dark current level, flat normalization,
and science frame statistics. This approach ensures the verification adapts to the actual
data rather than relying on hardcoded synthetic parameters.

## Key Technical Details

- All frames are real CCD readouts with authentic noise characteristics
- Bias level, read noise, dark current rate, and flat-field response are properties of the
  actual Palomar LFC detector
- The flat-field pattern reflects real optical vignetting and pixel sensitivity variations
- Science frames contain real astronomical objects observed through the telescope
