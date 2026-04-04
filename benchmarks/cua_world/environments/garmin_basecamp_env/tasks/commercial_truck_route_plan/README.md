# commercial_truck_route_plan

## Overview

**Occupation**: Transportation Dispatcher (for Heavy and Tractor-Trailer Truck Drivers)
**Industry**: Transportation and Material Moving
**Difficulty**: Very Hard
**Timeout**: 600 seconds | **Max Steps**: 90

Heavy and Tractor-Trailer Truck Drivers are the #1 occupation by economic importance for
Garmin BaseCamp ($399M GDP). Dispatchers and drivers use BaseCamp constantly for route
planning with bridge height/weight restriction waypoints, mandatory weigh station stops,
and delivery sequencing — then upload the resulting GPX to their Garmin fleet devices.

## Domain Context

A Transportation Dispatcher at a commercial freight company must plan the weekly
Boston-to-Fall River delivery run for a fully-loaded 18-wheel tractor-trailer. The
driver needs a Garmin device data package containing: all delivery stops with dock
information, a known bridge height hazard on Route 116, the mandatory weigh station,
and a rest stop — all connected by a single optimized delivery route.

## Goal

Build a complete GPS data package in Garmin BaseCamp (starting from an empty library):

- **7 waypoints** with exact names, coordinates, symbols, and comments
- **1 route** named BOSTON-FALL RIVER FREIGHT RUN connecting the delivery stops in order
- **GPX export** saved to the Desktop as `BostonFallRiver_FreightRoute.gpx`

## Waypoints Required

| Name | Lat | Lon | Symbol | Comment |
|------|-----|-----|--------|---------|
| DEPOT SOUTH BOSTON | 42.3388 | -71.0502 | Building | Home depot. Loading dock hrs 05:00-22:00. Truck entrance off Tide St. |
| BRIDGE HAZARD RT116 | 42.1875 | -71.3285 | Danger | CLEARANCE 13'2"! NO TRUCKS OVER 13'2". Alternate: take I-495 S to Rte 1 S. |
| STOP 1 NORTON DIST | 41.9749 | -71.1849 | Waypoint | Norton Distribution Center. Dock B. Contact 508-555-0177. Est. arrival 09:30. |
| WEIGH STATION RT44 | 41.9275 | -71.0142 | Car | MANDATORY stop for oversize/overweight permits. Max axle load 40,000 lbs. |
| STOP 2 TAUNTON CTR | 41.8993 | -71.0940 | Waypoint | Taunton Industrial Park. Gate code 4821. Dock 3-7. Est. arrival 11:15. |
| STOP 3 FALL RIVER IND | 41.7004 | -71.1548 | Waypoint | Fall River Industrial Park. Large-format. Load bay 7-10. Est. arrival 13:00. |
| REST STOP I95 S | 41.6543 | -71.0432 | Waypoint | Certified truck parking. 78 spaces. Facilities available. 10hr rest limit. |

## Route Required

**BOSTON-FALL RIVER FREIGHT RUN**
Order: DEPOT SOUTH BOSTON → STOP 1 NORTON DIST → WEIGH STATION RT44 → STOP 2 TAUNTON CTR → STOP 3 FALL RIVER IND → REST STOP I95 S

*(Note: BRIDGE HAZARD RT116 is a map reference waypoint, not a route stop. The driver
sees it on the map for awareness but the route uses I-495 to bypass it.)*

## Export

Export entire My Collection as GPX to:
`C:\Users\Docker\Desktop\BostonFallRiver_FreightRoute.gpx`

## Starting State

BaseCamp starts with an empty library (Clear-BaseCampData). The agent must create all
waypoints and routes from scratch.

## Scoring (100 pts, pass ≥ 60)

| Criterion | Points |
|-----------|--------|
| GPX file exists (gate) | 0 (gate) |
| GPX file is new/post-task (gate) | 0 (gate) |
| 7 required waypoints present | 7 × 6 = 42 pts |
| Route BOSTON-FALL RIVER FREIGHT RUN found | 8 pts |
| Route has correct 6-point order | 12 pts |
| BRIDGE HAZARD has Danger symbol + clearance comment | 10 pts |
| DEPOT SOUTH BOSTON has Building symbol | 8 pts |
| WEIGH STATION RT44 has Car symbol | 8 pts |
| Any 3 STOP waypoints have arrival/dock comments | 12 pts |
| **Total** | **100 pts** |

## Verification Strategy

1. `export_result.ps1` (post_task hook):
   - Closes BaseCamp
   - Reads task start timestamp
   - Checks if `BostonFallRiver_FreightRoute.gpx` exists on Desktop and is newer than task start
   - Parses GPX XML: extracts waypoints (name, sym, cmt, lat, lon) and routes (name, points)
   - Writes JSON to `C:\Users\Docker\commercial_truck_route_plan_result.json`

2. `verifier.py`:
   - Copies JSON via `copy_from_env`
   - Gates on `gpx_exists=True` AND `gpx_is_new=True`
   - Scores each criterion independently

## Data Provenance

All locations are real geographic places in southeastern Massachusetts:
- South Boston freight/logistics district: ~42.34°N, 71.05°W
- Route 116 Millis area bridge: ~42.19°N, 71.33°W (bridges with low clearances common on state routes)
- Norton/Attleboro industrial area: ~41.97°N, 71.18°W
- Route 44 weigh station (Raynham area): ~41.93°N, 71.01°W
- Taunton industrial park: ~41.90°N, 71.09°W
- Fall River industrial park: ~41.70°N, 71.15°W
- I-95 southbound rest area near RI border: ~41.65°N, 71.04°W
