# Task: Multi-source Spectral Integration

## Occupation
Remote Sensing Scientist — combining multi-spectral satellite data for analysis.

## Industry
Environmental Monitoring / Remote Sensing Research

## Scenario
A remote sensing scientist receives two separate Sentinel-2 spectral band files (Red and NIR) that must be combined into a single product and used to derive vegetation indices. The agent must figure out how to merge two separate products in SNAP (e.g., Collocation, Stack, or other method) and then compute a derived spectral index.

## Data
- **Source**: Copernicus Sentinel-2A L2A bands from AWS COGs
- **Files**: sentinel2_B04_red.tif (Red), sentinel2_B08_nir.tif (NIR)

## What Makes This Very Hard
- Agent must discover how to combine two separate products (Collocation tool is not obvious)
- Agent must open and manage two products simultaneously
- Agent must derive an appropriate vegetation index (formula not given)
- No UI path hints — agent discovers all navigation independently

## Verification (6 criteria, 100 pts, pass at 70)
1. Integrated product saved in DIMAP (15 pts)
2. Multi-source bands present from both inputs (25 pts)
3. Derived spectral index band exists (20 pts)
4. Index expression references both source bands (15 pts)
5. GeoTIFF exported (15 pts)
6. GeoTIFF has non-trivial size (10 pts)
