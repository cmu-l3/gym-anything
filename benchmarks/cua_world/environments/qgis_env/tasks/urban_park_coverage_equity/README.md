# Task: Urban Park Coverage Equity

## Overview
This task tests polygon intersection and area computation in a projected CRS — one of the most geometrically demanding QGIS operations. The agent must intersect park polygons with census tract polygons, compute areas in square meters (requiring projected CRS), calculate coverage percentage, classify tracts by greenspace adequacy, and produce both GeoJSON and equity summary CSV outputs.

## Domain Context
Urban planners and sustainability specialists conduct greenspace equity audits to direct park investment toward underserved census tracts. This task uses real data: OpenStreetMap park polygons for the Portland metro area and US Census 2020 tracts for Multnomah County. Computing accurate areas and overlaps requires working in a metric projected coordinate system.

## Target Data
- **Input 1**: `/home/ga/GIS_Data/portland_parks_osm.geojson`
  - OpenStreetMap parks, recreation areas, and greenspaces (polygon layer)
  - Portland metro area bounding box
- **Input 2**: `/home/ga/GIS_Data/portland_census_tracts.geojson`
  - 2020 Census tracts for Multnomah County, Oregon
  - Fields: `GEOID`, `pop20` (population)
- **Expected output 1**: `/home/ga/GIS_Data/exports/park_coverage_by_tract.geojson`
  - All census tracts with computed coverage fields
- **Expected output 2**: `/home/ga/GIS_Data/exports/greenspace_equity_summary.csv`
  - Columns: `greenspace_tier`, `tract_count`, `total_pop`, `avg_park_pct`

## Task Description
The agent must:
1. Load both layers and reproject to a metric CRS (e.g., EPSG:32610 or EPSG:2269)
2. Intersect park polygons with census tracts (Vector > Geoprocessing > Intersection)
3. For each tract, sum the intersected park area in square meters
4. Compute tract area in square meters
5. Compute `park_pct = 100 * park_area_sqm / tract_area_sqm`
6. Classify: `adequate` (≥10%), `marginal` (5–9.99%), `deficient` (<5%)
7. Export enriched tracts GeoJSON and equity summary CSV

## Success Criteria
1. Output GeoJSON exists, is valid, and was created during this session (gate, 15 pts)
2. All four required fields present: `park_area_sqm`, `tract_area_sqm`, `park_pct`, `greenspace_tier` (15 pts)
3. Feature count covers ≥ 85% of expected census tracts (10 pts)
4. Area values indicate projected CRS used (tract areas > 10,000 sq m, not sq degrees) (15 pts)
5. `park_pct` values within ±3 percentage points of GT for ≥ 55% of tracts (20 pts)
6. `greenspace_tier` internally consistent with computed `park_pct` for ≥ 60% (15 pts)
7. Equity summary CSV with tier-level aggregation exported (10 pts)

## Verification Strategy
- **setup_task.sh**: Downloads OSM parks via Overpass API + TIGER 2020 tracts; computes GT using shapely intersection + pyproj (EPSG:32610); saves to `/tmp/gt_park_coverage.json`
- **export_result.sh**: Parses output GeoJSON; checks area magnitudes for CRS validation; compares GT; writes `/tmp/park_coverage_result.json`
- **verifier.py**: Reads task-specific result JSON; applies file_is_new gate; independently re-validates GeoJSON (Pattern 8); applies partial credit scoring
- Pass threshold: 60 points

## Edge Cases
- Using geographic CRS (degrees) for area will produce near-zero values and fail CRS check
- Parks that cross tract boundaries must be clipped (not just counted within) for accurate area
- Tracts with zero park overlap should have `park_area_sqm = 0.0` and `park_pct = 0.0`
- Agent may use QGIS "Intersection" tool or Field Calculator with `$area` after reprojection
