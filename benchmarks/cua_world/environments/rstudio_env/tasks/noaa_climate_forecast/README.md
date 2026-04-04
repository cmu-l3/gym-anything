# NOAA Climate Forecast Task

## Overview

An atmospheric scientist at a climate research institute analyzes the **NASA GISTEMP v4**
global mean surface temperature anomaly record (1880–2023) to characterize warming trends,
produce a 10-year forecast, and identify structural breakpoints in the climate record.

**Occupation:** Atmospheric Scientist / Climate Researcher
**Difficulty:** very_hard
**Dataset:** NASA GISTEMP v4 (downloaded live from NASA GISS)

---

## Dataset

| Field | Details |
|-------|---------|
| Source | https://data.giss.nasa.gov/gistemp/tabledata_v4/GLB.Ts+dSST.csv |
| Type | Real NASA GISS observational temperature anomaly record |
| Coverage | 1880 to 2023 (144 years of monthly anomalies) |
| Baseline | 1951–1980 average (anomalies expressed relative to this period) |

### File Format

The GISTEMP CSV has a metadata header row followed by data with columns:
`Year, Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec, J-D, D-N, DJF, MAM, JJA, SON`

Missing monthly values are marked as `***` and must be handled.

---

## Task Goal

Produce four deliverables from the annual temperature anomaly record:

1. **STL decomposition** (`climate_stl_components.csv`)
   Columns: `year, observed, trend, seasonal, remainder`
   Compute annual averages (Jan–Dec mean, skipping `***`), then apply `stats::stl()`
   Expected: ~144 rows, strongly positive trend component

2. **ARIMA forecast** (`climate_forecast.csv`)
   Columns: `year, forecast, lower80, upper80, lower95, upper95`
   Use `forecast::auto.arima()` on the STL trend component, forecast 2024–2033 (10 rows)
   Expected: forecasts around 1.1–1.6°C anomaly by 2033

3. **Changepoint detection** (`climate_breakpoints.csv`)
   Columns: `breakpoint_year, segment_mean_before, segment_mean_after`
   Use `changepoint::cpt.mean()` or `cpt.var()` on the trend component
   Expected: at least 1 breakpoint (~1975–1985 rapid warming onset)

4. **3-panel figure** (`climate_analysis.png`)
   Top panel: observed annual anomaly with STL trend overlay
   Middle panel: ARIMA forecast with 80%/95% CI bands (2024–2033)
   Bottom panel: changepoint visualization with segment means marked

---

## Expected Results

| Metric | Expected Value |
|--------|---------------|
| 1880 annual anomaly | ~−0.16°C |
| 2023 annual anomaly | ~+1.17°C |
| Overall warming since 1880 | ~1.3°C |
| ARIMA forecast 2033 | ~1.1–1.6°C anomaly |
| Changepoint count | ≥1 (likely 1977–1985) |
| STL seasonal component | Small (annual data; seasonal ≈ 0) |

---

## Verification Strategy

### Criterion 1: STL Decomposition CSV (25 pts)
- File exists and is newer than task start (10 pts)
- Has `trend` column (10 pts)
- Has ≥100 rows covering full historical record (5 pts)

### Criterion 2: ARIMA Forecast CSV (25 pts)
- File exists and is new (10 pts)
- Has forecast + CI columns (10 pts)
- Has 10 rows (2024–2033 horizon) (5 pts)

### Criterion 3: Changepoints CSV (20 pts)
- File exists and is new (10 pts)
- Has `breakpoint_year` and segment mean columns (10 pts)

### Criterion 4: 3-panel Plot PNG (30 pts)
- File exists and is new (10 pts)
- Valid PNG header (5 pts)
- File size ≥ 100KB (suggests 3-panel layout) (15 pts)

**Score cap gates**: forecast CSV and breakpoints CSV are required; missing either caps score at 59.

**VLM bonus**: Up to 10 additional points from visual inspection of RStudio screenshot.

---

## Edge Cases

- GISTEMP CSV has a comment row at the top — agents must skip it (`skip=2` in `read.csv`)
- `***` entries for missing months must be converted to `NA` before computing annual means
- `stl()` requires a seasonal period: for annual data created as `ts(x, frequency=1)`, use `s.window="periodic"` or apply STL with `frequency=10` (decadal seasonality)
- The `changepoint` package uses `cpt.mean()` by default with BIC or AIC method selection
- Network required: dataset downloaded from NASA GISS at task setup
