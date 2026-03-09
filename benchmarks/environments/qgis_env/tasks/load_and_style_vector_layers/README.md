# Task: Load and Style Vector Layers

## Overview
This task tests the fundamental GIS workflow of importing vector data layers into QGIS and applying distinct visual styles (symbology) to each. Layer styling is a core daily task for any GIS professional—making spatial data readable and visually distinguishable is essential for map interpretation and analysis.

## Domain Context
In a typical GIS project, a professional receives raw geospatial data files (Shapefiles, GeoJSON, GeoPackage) and must load them into a project, apply appropriate color schemes and symbol sizes to distinguish different data types, then save the project for future use. This task mirrors that exact workflow using polygon zones and point locations in the San Francisco Bay Area.

## Target Data
- **Polygon layer**: `/home/ga/GIS_Data/sample_polygon.geojson`
  - 2 polygon features: "Area A" (area_sqkm=10.5) and "Area B" (area_sqkm=8.2)
  - CRS: WGS84 (EPSG:4326)
  - Covers San Francisco Bay Area (lon -122.5 to -121.9, lat 37.5 to 37.8)
- **Point layer**: `/home/ga/GIS_Data/sample_points.geojson`
  - 3 point features: "Point A" (elev=100), "Point B" (elev=150), "Point C" (elev=200)
  - CRS: WGS84 (EPSG:4326)

## Task Description
1. Open QGIS (already running from setup)
2. Add polygon layer via Layer > Add Layer > Add Vector Layer
3. Add point layer via same method
4. Style polygons: blue fill, semi-transparent (~50-70% opacity)
5. Style points: red circle markers, 4.0 mm size
6. Save project as `styled_layers.qgz` in `/home/ga/GIS_Data/projects/`

## Success Criteria
1. Project file exists at `/home/ga/GIS_Data/projects/styled_layers.qgz` (or .qgs)
2. Project file is valid format (XML for .qgs, ZIP for .qgz)
3. Polygon layer `sample_polygon` is loaded in the project
4. Point layer `sample_points` is loaded in the project
5. Project contains 2+ layers
6. Project file has substantial size (>2KB, indicating styled content)

## Verification Strategy
- **export_result.sh** extracts QGS from QGZ, parses XML to find layer names via grep
- **verifier.py** checks 6 criteria with weighted scoring (total 100 points)
- Baseline recording: initial project count saved before task starts
- Pass threshold: 65 points

## Edge Cases
- Agent may save as .qgs instead of .qgz — both are accepted
- Agent may name layers differently (e.g., with path prefix) — partial name matching used
- Agent may not close property dialogs — doesn't affect saved project
