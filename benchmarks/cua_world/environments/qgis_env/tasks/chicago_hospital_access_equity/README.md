# Task: Chicago Hospital Access Equity

## Overview
This task tests multi-layer spatial analysis combining proximity computation, distance-based counting, and field classification in QGIS. The agent must compute centroid-to-point distances across all community areas, count nearby hospitals within a radius, classify each area by access tier, and produce both a GeoJSON and CSV output. Accurate distance calculation requires using a projected coordinate reference system.

## Domain Context
Public health GIS analysts at county health departments routinely perform hospital access equity analyses to identify underserved communities and prioritize resource allocation for mobile clinics or facility siting. This task uses real data: HIFLD hospital locations and Chicago Data Portal community area boundaries, with 2020 census population estimates.

## Target Data
- **Input 1**: `/home/ga/GIS_Data/chicago_hospitals.geojson`
  - Chicago-area hospital point locations from HIFLD open data
  - Includes `NAME`, `STATE`, `CITY` fields
- **Input 2**: `/home/ga/GIS_Data/chicago_community_areas.geojson`
  - Chicago's 77 official community areas (polygon layer)
  - Fields: `community` (name), `pop_2020` (estimated population)
- **Expected output 1**: `/home/ga/GIS_Data/exports/hospital_access_equity.geojson`
  - All 77 community areas with added fields
- **Expected output 2**: `/home/ga/GIS_Data/exports/access_tier_summary.csv`
  - Summary with columns: `access_tier`, `community_count`, `total_population`

## Task Description
The agent must:
1. Load both layers in QGIS
2. Reproject to a metric CRS (e.g., EPSG:26916 or EPSG:3435) for distance accuracy
3. For each community area centroid, compute distance to the nearest hospital
4. Count hospitals within 5 km of each centroid
5. Classify: `high` (≥3 hospitals within 5 km), `medium` (1–2), `low` (0)
6. Export enriched community areas to GeoJSON
7. Export a summary CSV aggregating by access_tier

## Success Criteria
1. Output GeoJSON exists, is valid, and was created during this session (gate, 15 pts)
2. All three required fields present: `nearest_hosp_km`, `hosp_count_5km`, `access_tier` (15 pts)
3. All 77 community areas included (15 pts)
4. `nearest_hosp_km` values within ±1 km of GT for ≥ 60% of areas (20 pts)
5. `access_tier` internally consistent with computed `hosp_count_5km` for ≥ 65% (20 pts)
6. Summary CSV exported with correct column structure (15 pts)

## Verification Strategy
- **setup_task.sh**: Downloads real Chicago data; computes GT hospital distances using haversine; saves to `/tmp/gt_hospital_access.json`
- **export_result.sh**: Parses output GeoJSON and CSV; compares against GT; writes `/tmp/hospital_access_result.json`
- **verifier.py**: Reads task-specific result JSON; applies file_is_new gate; independently re-validates GeoJSON (Pattern 8); applies partial credit scoring
- Pass threshold: 60 points

## Edge Cases
- Distance accuracy depends on CRS — geographic CRS (degrees) will fail the ±1 km tolerance
- Agent may use "Hub Distance" tool, "Distance Matrix", or manual Python computation
- `hosp_count_5km` tolerance: GT re-derived from agent's own values for tier classification fairness
- Alternative filename search included: `*hospital*access*`, `*access*equity*`
