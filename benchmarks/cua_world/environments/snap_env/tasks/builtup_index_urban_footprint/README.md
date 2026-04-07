# Compound Built-Up Index and Urban Footprint Mapping (`builtup_index_urban_footprint@1`)

## Overview
This task evaluates the agent's ability to chain multiple spectral index computations in ESA SNAP, apply boolean thresholding to a derived compound index, and extract statistical data. The agent must derive NDVI and NDBI, combine them into a Built-Up Index (BUI) to suppress bare-soil noise, create an urban footprint mask, and export both raster data and statistical summaries.

## Rationale
**Why this task is valuable:**
- Tests the chaining of multiple Band Maths formulas sequentially (indices built upon other indices)
- Requires mapping conceptual formulas to specific file-dependent band names
- Evaluates conditional boolean logic for feature extraction
- Exercises SNAP's analytical UI (Statistics tool) for exporting structured textual data
- Demands multi-format export (BEAM-DIMAP for workspace, GeoTIFF for GIS interoperability, TXT for reporting)

**Real-world Context:** A municipal urban planner is updating the city's master plan and needs to quantify the expansion of impervious surfaces (concrete, asphalt, buildings). Because bare soil often gets misclassified as urban area when using standard methods, they must compute a compound Built-Up Index (BUI) which subtracts the Vegetation Index (NDVI) from the Built-up Index (NDBI) to accurately map the urban footprint. 

## Task Description

**Goal:** Open a 4-band Landsat image, derive NDVI and NDBI to compute a compound Built-Up Index (BUI), generate a binary urban footprint mask, and export the mask and BUI statistics.

**Starting State:** ESA SNAP Desktop is open and maximized. The target file is available at `~/snap_data/landsat_multispectral.tif`. The directories `~/snap_projects/` and `~/snap_exports/` exist.

**Expected Actions:**
1. Open the file `~/snap_data/landsat_multispectral.tif` in SNAP. This file contains 4 bands: Band 1 (SWIR1), Band 2 (NIR), Band 3 (Red), and Band 4 (Green).
2. Using the **Band Maths** tool, calculate the following virtual bands (use exact names):
   - `NDVI` (Normalized Difference Vegetation Index) formula: `(NIR - Red) / (NIR + Red)` -> `(band_2 - band_3) / (band_2 + band_3)`
   - `NDBI` (Normalized Difference Built-up Index) formula: `(SWIR1 - NIR) / (SWIR1 + NIR)` -> `(band_1 - band_2) / (band_1 + band_2)`
   - `BUI` (Built-Up Index) formula: `NDBI - NDVI` (You may use the intermediate bands or expand the full formula)
   - `urban_footprint`: A binary mask where pixels with `BUI > 0` are mapped to 1 (built-up), and all other pixels are 0.
3. Save the enriched product containing all original and derived bands as a BEAM-DIMAP file to `~/snap_projects/urban_analysis.dim`.
4. Export the product containing the `urban_footprint` mask as a GeoTIFF to `~/snap_exports/urban_footprint.tif` (it is acceptable if the exported GeoTIFF contains other bands as well).
5. Open the **Statistics** tool in SNAP (via the Analysis menu), compute the statistics for the `BUI` band, and export the results using the tool's text export button to `~/snap_exports/bui_statistics.txt`.

**Final State:**
- A BEAM-DIMAP product exists at `~/snap_projects/urban_analysis.dim` containing the proper mathematical definitions for all derived bands.
- A GeoTIFF file exists at `~/snap_exports/urban_footprint.tif`.
- A text file exists at `~/snap_exports/bui_statistics.txt` containing the statistical summary of the BUI band.

## Verification Strategy

### Primary Verification: File-Based Metadata Inspection
The verifier programmatically inspects the saved outputs:
1. **DIMAP Existence & Structure:** Verifies `~/snap_projects/urban_analysis.dim` exists and contains at least 8 bands (4 original + 4 derived).
2. **Mathematical Logic Validation:** Parses the `.dim` XML file to extract the `<MDATTR name="expression" type="ascii">` for `NDVI`, `NDBI`, `BUI`, and `urban_footprint`. Validates that the expressions map correctly to the bands defined in the task (e.g., NDVI uses `band_2` and `band_3`).
3. **GeoTIFF Export Check:** Uses file system checks to verify `~/snap_exports/urban_footprint.tif` exists and has a non-trivial file size (>10KB).
4. **Statistics Extraction Check:** Reads `~/snap_exports/bui_statistics.txt` to confirm it is not empty and contains expected statistical keywords (e.g., "Mean", "Sigma", "Minimum", "Maximum") specifically for the BUI band.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| DIMAP Project Saved | 15 | `urban_analysis.dim` and `.data` folder exist in the correct directory |
| Correct NDVI/NDBI Expressions | 25 | XML contains correctly mapped algebraic formulas for NDVI and NDBI |
| Correct BUI & Mask Expressions | 25 | XML contains BUI derivation and correct threshold logic (`> 0`) |
| GeoTIFF Mask Exported | 15 | `urban_footprint.tif` exists with valid size |
| BUI Statistics Exported | 20 | `bui_statistics.txt` exists, is formatted correctly, and contains BUI data |
| **Total** | **100** | |

**Pass Threshold:** 65 points, requiring at least the DIMAP project to be saved with correct foundational Band Maths logic.