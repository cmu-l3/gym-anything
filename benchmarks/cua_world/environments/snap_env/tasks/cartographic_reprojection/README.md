# Task: Cartographic Reprojection

## Occupation
GIS Technologist — preparing satellite imagery for map production.

## Industry
Cartography / Topographic Mapping / Geospatial Data Management

## Scenario
A GIS technologist must transform satellite imagery from its native geographic CRS to a projected coordinate system suitable for national-scale topographic mapping, then create a spatial subset focusing on the area of interest. The agent must discover SNAP's reprojection and subset tools, choose an appropriate map projection, and produce correctly georeferenced output.

## Data
- **Source**: Sentinel-2 B4,B3,B2 bands from leftfield-geospatial/homonim
- **File**: sentinel2_b432.tif (3-band RGB)

## What Makes This Very Hard
- Agent must discover Reprojection tool in SNAP (no menu path given)
- Agent must choose an appropriate projected CRS (not told which one)
- Agent must also apply a Subset operation (separate tool)
- Agent must chain two distinct SNAP operations in correct order
- No UI path hints — agent discovers all navigation independently

## Verification (6 criteria, 100 pts, pass at 70)
1. Product saved in DIMAP format (15 pts)
2. CRS changed to projected coordinate system (25 pts)
3. Spatial subset applied (dimensions changed) (20 pts)
4. Bands preserved in output (15 pts)
5. GeoTIFF exported (15 pts)
6. GeoTIFF has non-trivial size (10 pts)
