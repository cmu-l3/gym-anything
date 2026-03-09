# Spatial Kriging Soil Task

## Overview

A remote sensing technician and spatial analyst performs a **geostatistical soil contamination
assessment** using the classic Meuse river dataset. The task involves variogram fitting,
ordinary kriging interpolation on a prediction grid, and spatial autocorrelation testing.

**Occupation:** Remote Sensing Technician / Spatial Analyst
**Difficulty:** very_hard
**Dataset:** `sp::meuse` + `sp::meuse.grid` (built into the `sp` R package)

---

## Dataset

| Field | Details |
|-------|---------|
| Source | `sp` R package built-in dataset |
| Reference | Pebesma EJ, Bivand RS (2005). *R News* 5(2), 9–13 |
| N samples | 155 georeferenced soil samples |
| Grid points | 3,103 prediction cells (40m × 40m) |
| Location | Meuse river flood plain, Netherlands |
| CRS | Dutch RD New (EPSG:28992) — coordinates in meters |

### Variables (meuse)

- `x`, `y` — RD coordinates (meters)
- `zinc` — zinc concentration (ppm) — **analysis target**
- `cadmium`, `copper`, `lead` — other heavy metals
- `elev` — elevation above flood plain
- `dist` — normalized distance to river
- `soil`, `lime`, `landuse` — categorical site properties

---

## Task Goal

Produce four deliverables:

1. **Variogram model CSV** (`zinc_variogram.csv`)
   Columns: `model, nugget, sill, range_m`
   Fit empirical variogram to log-transformed zinc (`log(zinc)`) using `gstat::variogram()`
   Fit theoretical model (spherical or exponential) via `gstat::fit.variogram()`
   Expected: range ≈ 200–1500m, psill ≈ 0.3–1.0, nugget ≈ 0.0–0.3

   **Also produce**: `zinc_variogram_points.csv` with columns `dist, gamma, np`
   (the empirical variogram points used for fitting)

2. **Kriging predictions CSV** (`zinc_kriging_predictions.csv`)
   Columns: `x, y, zinc_pred, zinc_var`
   Perform ordinary kriging on `meuse.grid` (3,103 cells)
   `zinc_pred` should be back-transformed to original scale: `exp(prediction)`
   Expected: predictions in range ~50–3000 ppm

3. **Moran's I test CSV** (`zinc_moran_test.csv`)
   Columns: `statistic, expected, variance, p_value, significant`
   Test for spatial autocorrelation using `ape::Moran.I()` or `spdep::moran.test()`
   Apply to log-transformed zinc values or OK residuals
   Expected: significant positive autocorrelation (p < 0.05)

4. **2-panel spatial map** (`zinc_kriging_map.png`)
   Left panel: bubble map of observed zinc concentrations at 155 sample locations
   Right panel: kriging prediction map of full flood plain with color scale
   Expected file size > 150KB (spatial maps with color rasters are large)

---

## Expected Results

| Metric | Expected Value |
|--------|---------------|
| Zinc min/max | 113–1839 ppm |
| Log-zinc variogram range | 200–1500 m |
| Log-zinc nugget | 0.0–0.3 |
| Log-zinc psill | 0.3–1.0 |
| Kriging predictions | ~3103 grid cells |
| Moran's I p-value | < 0.05 (significant spatial autocorrelation) |

---

## Verification Strategy

### Criterion 1: Variogram Model CSV (25 pts)
- File exists and is new (10 pts)
- Has nugget/sill/range columns (10 pts)
- Parameters in valid geostatistical range (5 pts)

### Criterion 2: Kriging Predictions CSV (30 pts)
- File exists and is new (12 pts)
- Has x, y, prediction columns (10 pts)
- ≥200 rows (full grid coverage) (8 pts)

### Criterion 3: Moran's I Test CSV (15 pts)
- File exists and is new (8 pts)
- Has statistic and p-value columns (7 pts)

### Criterion 4: 2-panel Spatial Map PNG (30 pts)
- File exists and is new (10 pts)
- Valid PNG header (5 pts)
- File size ≥ 150KB (suggests full spatial map with color) (15 pts)

**Score cap gates**: variogram CSV, predictions CSV, and Moran test CSV are all required;
missing any one of them caps score at 59 (below pass threshold of 60).

**VLM bonus**: Up to 10 additional points from visual inspection of RStudio screenshot.

---

## Edge Cases

- `coordinates(meuse) <- ~x+y` must be called before variogram/kriging
- `gridded(meuse.grid) <- TRUE` is required for kriging prediction grid
- `fit.variogram()` may fail with some initial parameter choices; try `fit.sill=TRUE, fit.range=TRUE`
- For Moran's I with `ape::Moran.I()`, a weight matrix is required — use inverse distance weights
- `spdep::moran.test()` requires a `listw` object (use `spdep::knearneigh()` + `spdep::nb2listw()`)
- Back-transformation: if kriging is done on log scale, use `exp()` for predictions (bias correction is optional)
- The `meuse.grid` object provides ~3103 prediction locations covering the flood plain
