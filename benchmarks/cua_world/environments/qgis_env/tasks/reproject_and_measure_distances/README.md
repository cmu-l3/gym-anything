# Task: Reproject and Measure Distances

## Overview
This task tests CRS reprojection and field calculation—two essential GIS skills. The agent must reproject a road network from geographic CRS (degrees) to a projected CRS (meters), calculate each road's length using the Field Calculator, and export the results as a CSV table. This multi-step workflow combines coordinate system understanding, geoprocessing, and data export.

## Domain Context
A transportation analyst receives road data in WGS84 (latitude/longitude) and needs to produce a table of road lengths in kilometers for a planning report. Since WGS84 uses degrees, not meters, accurate length measurement requires reprojecting to a local metric CRS (UTM zone 10N for the San Francisco Bay Area). The analyst then uses the Field Calculator to compute `$length / 1000` and exports the attribute table as CSV.

## Target Data
- **Input**: `/home/ga/GIS_Data/sample_lines.geojson`
  - 2 line features: "Road 1" (highway, 3 vertices), "Road 2" (secondary, 2 vertices)
  - CRS: WGS84 (EPSG:4326)
- **Expected outputs**:
  - Reprojected GeoJSON: `/home/ga/GIS_Data/exports/roads_utm.geojson` (EPSG:32610)
  - CSV with lengths: `/home/ga/GIS_Data/exports/road_measurements.csv`

## Task Description
1. Open QGIS (already running)
2. Load `sample_lines.geojson`
3. Reproject to EPSG:32610 (UTM zone 10N) via Export > Save Features As
4. Open attribute table of reprojected layer
5. Toggle editing, open Field Calculator
6. Create new field `length_km` (Decimal) with expression `$length / 1000`
7. Save edits
8. Export as CSV to `/home/ga/GIS_Data/exports/road_measurements.csv`

## Success Criteria
1. CSV file exists at expected path
2. CSV is valid with parseable structure
3. Contains exactly 2 data rows (Road 1 and Road 2)
4. Has a length-related field with numeric values
5. Length values are positive and plausible (0.1 to 500 km range)
6. Both road names present in the CSV
7. Reprojected GeoJSON also created

## Verification Strategy
- **export_result.sh** uses Python csv module to parse output, validate headers, check numeric values
- **verifier.py** checks 7 criteria with weighted scoring (total 100 points)
- Baseline recording: initial CSV and GeoJSON counts
- Pass threshold: 55 points

## Edge Cases
- Agent may name the length field differently (e.g., `len_km`, `length`) — any field with "length" in name accepted
- Agent may use different CRS (e.g., EPSG:3857) — accepted as long as lengths are computed
- Agent may calculate length in meters instead of km — values still within plausible range
- CSV may include geometry column (WKT) — doesn't affect validation
