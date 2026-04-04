# Task: Invasive Species State Expansion

## Overview
This task tests temporal filtering of point data, multi-run "Count Points in Polygon" operations, derived field computation, and status classification across two time periods. The agent must load occurrence data, filter by year ranges, join counts to state polygons, compute percentage change, and classify each state's invasion trajectory — then export both GeoJSON and CSV outputs.

## Domain Context
Conservation GIS analysts at wildlife agencies track invasive species spread across administrative boundaries to allocate management budgets. This task uses real GBIF occurrence records for Harmonia axyridis (Asian lady beetle) from 2005–2023 and Natural Earth US state boundaries, comparing an early period (2005–2012) against a recent period (2016–2023) to detect expanding invasions.

## Target Data
- **Input 1**: `/home/ga/GIS_Data/harmonia_us_occurrences.geojson`
  - GBIF occurrence records, US-only, 2005–2023
  - Each point has a `year` property
- **Input 2**: `/home/ga/GIS_Data/us_states.geojson`
  - Contiguous US state boundaries (Natural Earth 50m)
  - Fields: `name`, `postal`
- **Expected output 1**: `/home/ga/GIS_Data/exports/invasion_status_by_state.geojson`
  - States with at least 1 occurrence in either period
- **Expected output 2**: `/home/ga/GIS_Data/exports/invasion_summary.csv`
  - Columns: `invasion_status`, `state_count`, `total_occurrences_recent`

## Task Description
The agent must:
1. Load both layers in QGIS
2. Filter occurrences to two periods: 2005–2012 (early) and 2016–2023 (recent)
3. Run "Count Points in Polygon" twice (once per period) to get counts per state
4. Join both count results to the state layer
5. Compute `pct_change = 100*(recent - early)/early` (null if early == 0)
6. Classify invasion_status: `expanding`, `new_invasion`, `established`, `no_recent_activity`
7. Export enriched states GeoJSON and summary CSV

## Success Criteria
1. Output GeoJSON exists, is valid, and was created during this session (gate, 15 pts)
2. All four required fields present: `count_2005_2012`, `count_2016_2023`, `pct_change`, `invasion_status` (15 pts)
3. Feature count covers ≥ 80% of expected states with occurrences (15 pts)
4. Period occurrence counts match GT within ±1 for ≥ 60% of states (25 pts)
5. `invasion_status` internally consistent with computed counts for ≥ 60% (20 pts)
6. Summary CSV with `invasion_status` and count columns exported (10 pts)

## Verification Strategy
- **setup_task.sh**: Downloads GBIF data + Natural Earth states; computes GT invasion status per state using shapely; saves to `/tmp/gt_invasion.json`
- **export_result.sh**: Parses output GeoJSON and CSV; compares against GT; writes `/tmp/invasion_result.json`
- **verifier.py**: Reads task-specific result JSON; applies file_is_new gate; independently re-validates GeoJSON (Pattern 8); applies partial credit scoring
- Pass threshold: 60 points

## Edge Cases
- GBIF data volume varies (2 pages × 300 records); some states near boundaries may differ by ±1
- Agent hint: "Count Points in Polygon" twice (one per time period), then join results
- `invasion_status` re-derived from agent's own counts for classification fairness
- States with occurrences in only one period should still appear in output
