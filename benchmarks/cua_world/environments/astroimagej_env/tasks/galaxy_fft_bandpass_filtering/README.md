# Enhance Galaxy Spiral Arms using FFT Bandpass Filtering (`galaxy_fft_bandpass_filtering@1`)

## Overview
Astronomical images often contain signals across multiple spatial scales: large-scale gradients from diffuse halos or sky background, intermediate-scale structures like galaxy spiral arms, and high-frequency noise from the detector. This task requires the agent to use a Fast Fourier Transform (FFT) bandpass filter in AstroImageJ to isolate intermediate spatial frequencies in an ultraviolet galaxy image, effectively enhancing the spiral arms while suppressing both background gradients and pixel noise.

## Rationale
**Why this task is valuable:**
- Tests the agent's ability to operate in the frequency domain using ImageJ's FFT tools
- Requires navigating complex dialogs with specific numerical parameters
- Evaluates the ability to distinguish between spatial scales (large background vs. small noise)
- Validates the saving of processed outputs and metadata reporting
- Real-world relevance: Morphological classification and structural analysis of galaxies often rely on unsharp masking or FFT filtering to reveal underlying density waves (spiral arms) hidden by the dominant exponential disk profile.

**Real-world Context:** An astronomer is preparing to measure the pitch angle of spiral arms in a Far-Ultraviolet (FUV) observation of a galaxy from the Ultraviolet Imaging Telescope (UIT). The raw image has a strong central glow and high-frequency noise that makes tracing the arms difficult. They need to run a 2D spatial bandpass filter to remove structures larger than 40 pixels (the diffuse disk) and smaller than 3 pixels (the noise), isolating the spiral structure into a new FITS file.

## Task Description

**Goal:** Apply an FFT Bandpass Filter to the UIT FUV galaxy image to isolate structures between 3 and 40 pixels, save the enhanced image, and record its overall statistics.

**Starting State:**
- AstroImageJ is launched and ready.
- The target image is located at `~/AstroImages/raw/uit_galaxy_sample.fits`.
- An empty output directory exists at `~/AstroImages/processed/`.

**Expected Actions:**
1. Open `~/AstroImages/raw/uit_galaxy_sample.fits` in AstroImageJ.
2. Navigate to `Process > FFT > Bandpass Filter...`.
3. Configure the filter dialog exactly as follows:
   - **Filter large structures down to:** 40 pixels
   - **Filter small structures up to:** 3 pixels
   - **Suppress stripes:** None
   - **Tolerance of direction:** 5%
   - **Autoscale after filtering:** Checked (Yes)
   - **Saturate image when autoscaling:** Unchecked (No)
4. Apply the filter. A new image window containing the filtered result will be generated.
5. Save this new filtered image as a FITS file to `~/AstroImages/processed/uit_bandpass_filtered.fits`.
6. Measure the full-image statistics (Mean, Standard Deviation, Min, and Max) of the *filtered* image (using `Analyze > Measure` or `Image > Show Info`).
7. Create a text report at `~/AstroImages/processed/filter_report.txt` containing the filter parameters used and the measured statistics.

**Final State:**
- A new FITS file `uit_bandpass_filtered.fits` exists in the `processed/` directory.
- A text report `filter_report.txt` exists with the requested data.
- The filtered FITS file shows suppressed background (reduced dynamic range between core and edges) compared to the original, confirming a high-pass spatial filter was applied.

## Verification Strategy

### Primary Verification: Programmatic FITS Analysis
A Python script utilizing `astropy.io.fits` and `numpy` will:
1. Verify the existence of `~/AstroImages/processed/uit_bandpass_filtered.fits`.
2. Load the original and the filtered FITS files.
3. Check that the dimensions match (512x512).
4. Verify the image transformation is consistent with an FFT Bandpass. A bandpass filter that removes large structures acts as a high-pass filter for the background, drastically reducing the large dynamic range caused by the galaxy's bright core compared to the edges. 
5. The export script measures the core-to-edge brightness ratio.

### Secondary Verification: VLM Trajectory & Report Parsing
1. The verifier will sample trajectory frames to ensure the agent navigated the AstroImageJ FFT Bandpass dialog.
2. The verifier will read `~/AstroImages/processed/filter_report.txt` to confirm the agent successfully extracted the image statistics and accurately reported the requested spatial frequency bounds.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| **File Exists & Created** | 10 | The FITS file exists and was created during the task |
| **Correct Dimensions** | 10 | The filtered image maintains the original dimensions |
| **Image Modified** | 10 | The image pixel array is demonstrably modified |
| **Background Flattening** | 25 | The filtered image statistics indicate large structures were successfully removed (reduced core contrast) |
| **Report File Exists** | 10 | `filter_report.txt` exists in the correct directory |
| **Report Accuracy** | 15 | The report correctly lists the "40" and "3" pixel parameters |
| **VLM Trajectory Checks** | 20 | VLM verifies the FFT Bandpass tool was used on screen |
| **Total** | **100** | |

Pass Threshold: 70 points