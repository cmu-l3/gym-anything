# Task: Spatial Join Points to Polygons

## Overview
This task tests spatial overlay analysis—specifically, a spatial join that determines which polygon zone each point falls within. This is a fundamental GIS operation used for zone assignment, demographic analysis, administrative boundary matching, and resource allocation.

## Domain Context
A common real-world scenario: a city planner has monitoring stations (points) and administrative zones (polygons) and needs to determine which zone each station belongs to, carrying over the zone attributes (name, area) to enrich the station data. This "Join Attributes by Location" operation is one of the most frequently used spatial analysis tools in QGIS.

## Target Data
- **Point layer**: `/home/ga/GIS_Data/sample_points.geojson` (3 features)
- **Polygon layer**: `/home/ga/GIS_Data/sample_polygon.geojson` (2 features)
- **Expected spatial relationships** (ground truth):
  - Point A (-122.4, 37.6) → falls within Area A
  - Point B (-122.3, 37.7) → falls within Area A
  - Point C (-122.1, 37.65) → falls within Area B

## Task Description
1. Open QGIS (already running)
2. Load `sample_polygon.geojson` and `sample_points.geojson`
3. Run Vector > Data Management Tools > Join Attributes by Location
4. Input layer: sample_points; Join layer: sample_polygon
5. Geometric predicate: within/intersects
6. Join type: one-to-one
7. Export result to `/home/ga/GIS_Data/exports/points_with_polygon_info.geojson`

## Success Criteria
1. Output file exists at expected path
2. File is valid GeoJSON
3. Contains exactly 3 features (all points matched)
4. All features have Point geometry (input geometry preserved)
5. Join fields present (area_sqkm and/or polygon name from join layer)
6. Join mapping is correct (Point A→Area A, Point B→Area A, Point C→Area B)
7. File is newly created

## Verification Strategy
- **export_result.sh** uses Python to parse output GeoJSON, check for joined attributes, verify correctness of point-to-polygon mapping
- **verifier.py** checks 7 criteria with weighted scoring (total 100 points)
- Baseline recording: initial export count
- Pass threshold: 55 points

## Edge Cases
- Join may create prefixed field names (e.g., `name_2`) to avoid collision — handled by checking all property values
- Agent may use "intersects" instead of "within" — both produce correct results for this data
- Some features may fail to join if CRS mismatch — not expected since both layers are WGS84
