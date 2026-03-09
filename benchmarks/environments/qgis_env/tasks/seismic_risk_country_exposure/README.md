# Task: Seismic Risk Country Exposure

## Overview
This task tests advanced spatial join and aggregation skills in a real-world catastrophe risk modeling context. The agent must join point data (earthquake epicenters) to polygon data (country boundaries), compute per-group statistics, classify features by a derived risk tier, and export a filtered output. It requires understanding of point-in-polygon spatial joins, attribute aggregation, and conditional field computation in QGIS.

## Domain Context
Seismic risk analysts at global reinsurance companies routinely produce country-level earthquake exposure summaries to inform catastrophe model inputs and underwriting decisions. This task replicates that workflow using live USGS feed data (M2.5+ earthquakes, last 30 days) joined to Natural Earth country boundaries.

## Target Data
- **Input 1**: `/home/ga/GIS_Data/earthquakes_month.geojson`
  - USGS M2.5+ earthquakes from the past 30 days (real-time feed, varies by run)
  - Point layer with `mag` (magnitude) property
- **Input 2**: `/home/ga/GIS_Data/world_countries.geojson`
  - Natural Earth country boundaries
  - Fields: `ADMIN` (country name), `ISO_A3` (ISO code)
- **Expected output**: `/home/ga/GIS_Data/exports/country_seismic_exposure.geojson`
  - Only countries with at least 1 earthquake epicenter
  - Added fields: `quake_count`, `mean_mag`, `max_mag`, `risk_tier`

## Task Description
The agent must:
1. Load earthquake and country boundary layers in QGIS
2. Perform a spatial join / point-in-polygon count to get earthquake counts per country
3. Compute mean and max magnitude per country
4. Classify each country: `low` (count < 5), `medium` (5–14), `high` (≥ 15)
5. Filter out countries with zero earthquakes
6. Export to `/home/ga/GIS_Data/exports/country_seismic_exposure.geojson`

## Success Criteria
1. Output GeoJSON exists and is a valid FeatureCollection (15 pts)
2. File was created during this task session, not pre-existing (gate)
3. All four required fields present with correct names (15 pts)
4. Feature count reasonable relative to GT active-earthquake countries (15 pts)
5. `quake_count` values match GT within ±2 for ≥ 60% of countries (25 pts)
6. `risk_tier` classification internally consistent with `quake_count` for ≥ 70% (20 pts)
7. No countries with zero earthquakes included (10 pts)

## Verification Strategy
- **setup_task.sh**: Downloads real USGS data + Natural Earth countries; computes GT stats per country using shapely point-in-polygon; saves to `/tmp/gt_seismic.json`
- **export_result.sh**: Parses output GeoJSON, compares against GT, writes `/tmp/seismic_risk_result.json`
- **verifier.py**: Reads task-specific result JSON, applies gates and partial-credit scoring
- Pass threshold: 60 points

## Edge Cases
- Earthquake feed changes daily — GT is computed from same data seeded at setup time
- Countries with shared borders may have edge-case point assignments (±1 tolerance allowed)
- Agent may use QGIS "Count Points in Polygon" tool or a manual spatial join via Python
- Alternative filename search included in export script (`*seismic*exposure*`, `*country*quake*`)
