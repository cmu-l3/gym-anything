# Task: Air Quality Monitor Coverage

## Overview
This task tests spatial join (point-in-polygon counting), distance computation for unmatched polygons, density calculation requiring projected areas, and status classification across all 58 California counties. The agent must load EPA monitoring site data and county boundaries, count monitors per county, compute distance-to-nearest-monitor for unmonitored counties, calculate monitoring density (monitors/km²), and export both GeoJSON and CSV outputs.

## Domain Context
Environmental compliance officers at state air quality agencies audit monitoring network coverage to identify gaps that affect regulatory compliance reporting and public health protection. This task uses real EPA AQS (Air Quality System) monitoring site data filtered to California, joined against US Census TIGER 2022 county boundaries.

## Target Data
- **Input 1**: `/home/ga/GIS_Data/epa_pm25_monitors_ca.geojson`
  - EPA AQS active monitoring sites in California (point layer)
  - Fields: `site_id`, `county_name`, `parameter` (PM2.5)
- **Input 2**: `/home/ga/GIS_Data/ca_counties.geojson`
  - California's 58 counties (polygon layer, TIGER 2022)
  - Fields: `NAME`, `FIPS`, `ALAND` (land area in m²)
- **Expected output 1**: `/home/ga/GIS_Data/exports/pm25_coverage_gaps.geojson`
  - All 58 counties with computed coverage fields
- **Expected output 2**: `/home/ga/GIS_Data/exports/monitoring_coverage_report.csv`
  - Columns: `county_name`, `fips`, `monitor_count`, `coverage_status`, `nearest_monitor_km`, `monitoring_density`

## Task Description
The agent must:
1. Load both layers and reproject to EPSG:3310 (California Albers) for metric computations
2. Run "Count Points in Polygon" to count EPA monitors per county
3. For counties with monitor_count == 0, compute distance from county centroid to nearest monitor
4. Compute county area in km² (use projected CRS, not ALAND field directly)
5. Compute `monitoring_density = monitor_count / county_area_km2`
6. Classify: `monitored` (≥1 monitor) or `gap` (0 monitors)
7. Export enriched counties GeoJSON and coverage report CSV

## Success Criteria
1. Output GeoJSON exists, is valid, and was created during this session (gate, 15 pts)
2. All four required fields present: `monitor_count`, `nearest_monitor_km`, `coverage_status`, `monitoring_density` (15 pts)
3. All 58 California counties represented (15 pts)
4. `monitor_count` values match GT within ±1 for ≥ 65% of counties (25 pts)
5. `coverage_status` internally consistent with `monitor_count` for ≥ 70% (20 pts)
6. Coverage report CSV with correct columns exported (10 pts)

## Verification Strategy
- **setup_task.sh**: Downloads EPA AQS sites.zip + TIGER county boundaries; computes GT using shapely point-in-polygon + pyproj area/distance; saves to `/tmp/gt_aq_coverage.json`
- **export_result.sh**: Parses output GeoJSON; validates monitoring_density magnitude to check projected CRS; compares GT; writes `/tmp/aq_coverage_result.json`
- **verifier.py**: Reads task-specific result JSON; applies file_is_new gate; independently re-validates GeoJSON (Pattern 8); applies partial credit scoring
- Pass threshold: 60 points

## Edge Cases
- `monitoring_density` with geographic CRS area would be orders of magnitude too large — CRS check in export script validates density magnitude
- `nearest_monitor_km` should be 0.0 (not null) for monitored counties
- Agent may use QGIS "Count Points in Polygon" + "Distance to nearest hub" for unmonitored counties
- Alternative filename search: `*pm25*`, `*air*quality*`, `*monitor*coverage*`
