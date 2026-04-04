# Task: Buffer Analysis and Export

## Overview
This task tests a core GIS geoprocessing workflow: creating buffer zones around point features. Buffer analysis is one of the most commonly used spatial operations in GIS—used for proximity analysis, impact zones, service areas, and environmental assessments. The agent must handle CRS reprojection (necessary for accurate metric distances) and export results.

## Domain Context
A typical real-world application: an environmental analyst needs to create 500-meter buffer zones around monitoring stations (represented as points) to define impact assessment areas. Since the source data is in geographic CRS (degrees), it must be reprojected to a metric CRS before buffering to ensure accurate distances. The resulting buffer polygons are then exported for use in downstream analysis.

## Target Data
- **Input**: `/home/ga/GIS_Data/sample_points.geojson`
  - 3 point features: Point A (-122.4, 37.6), Point B (-122.3, 37.7), Point C (-122.1, 37.65)
  - CRS: WGS84 (EPSG:4326)
- **Expected output**: `/home/ga/GIS_Data/exports/point_buffers.geojson`
  - 3 polygon features (one buffer per point)
  - Buffer distance: 500 meters

## Task Description
1. Open QGIS (already running)
2. Load `sample_points.geojson`
3. Reproject to EPSG:3857 (Pseudo-Mercator) for metric buffering
4. Run Vector > Geoprocessing Tools > Buffer (distance=500, segments=16)
5. Export buffer result to `/home/ga/GIS_Data/exports/point_buffers.geojson` in WGS84

## Success Criteria
1. Output file exists at expected path
2. File is valid GeoJSON FeatureCollection
3. Contains exactly 3 polygon features
4. All features have Polygon/MultiPolygon geometry type
5. All geometries are non-degenerate (have coordinates)
6. File is newly created (not pre-existing)

## Verification Strategy
- **export_result.sh** uses Python to parse GeoJSON, count features, validate geometry types
- **verifier.py** checks 6 criteria with weighted scoring (total 100 points)
- Baseline recording: initial export file count
- Pass threshold: 60 points

## Edge Cases
- Agent may use different CRS for buffering (e.g., UTM zone 10N) — acceptable as long as output is polygons
- Buffer distance may vary slightly due to CRS distortion — not checked, only geometry type matters
- Agent may save with different filename — alternative filename search included
