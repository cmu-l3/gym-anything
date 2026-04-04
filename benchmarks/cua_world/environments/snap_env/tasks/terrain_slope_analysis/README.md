# Task: Terrain Slope Analysis

## Occupation
Geotechnical Engineer / Cartographer — assessing terrain for infrastructure planning.

## Industry
Civil Engineering / Construction / Geospatial Analysis

## Scenario
A geotechnical engineer needs to evaluate an SRTM DEM to produce a terrain steepness measure and a construction suitability classification. The agent must figure out how to derive slope from elevation data and create meaningful classification zones using SNAP's tools.

## Data
- **Source**: SRTM DEM (`srtm_dem.tif`) from github.com/opengeos/data
- **Type**: Single-band elevation raster

## What Makes This Very Hard
- Agent must discover how to compute slope/gradient from elevation data (no formula given)
- Agent must decide on appropriate classification thresholds (no values given)
- Agent must chain: slope derivation + classification + save + export
- No UI path hints provided — agent discovers all navigation independently

## Verification (6 criteria, 100 pts, pass at 70)
1. Product saved in DIMAP format (15 pts)
2. Slope/gradient band exists (25 pts)
3. Classification band with conditional logic (25 pts)
4. Additional derived bands beyond original (10 pts)
5. GeoTIFF exported (15 pts)
6. GeoTIFF has non-trivial size (10 pts)
