# SAR Search Plan — Garmin BaseCamp Task

## Overview
**Difficulty**: Very Hard
**Occupation**: Search and Rescue (SAR) Operations Coordinator
**Industry**: Emergency Management / Public Safety
**Timeout**: 600 s | **Max Steps**: 100

## Scenario
A hiker is overdue in Middlesex Fells Reservation, MA. The SAR coordinator must build
a complete GPS data package in Garmin BaseCamp: six tactical waypoints with correct
symbols and operational notes, plus two team search routes, then export the whole
collection as a GPX file for distribution to field teams.

## Task Requirements

### Waypoints (6 total — create in My Collection)
| # | Name | Lat | Lon | Symbol | Comment |
|---|------|-----|-----|--------|---------|
| 1 | LKP - HAWTHORN RD | 42.4405 | -71.1035 | Flag, Blue | Last Known Position – Found cell ping 2024-11-15 14:30. Do NOT disturb site. |
| 2 | CP-ALPHA | 42.4440 | -71.1120 | Flag, Red | Search Sector Alpha HQ. Team leader: Brown. Priority: High. |
| 3 | CP-BRAVO | 42.4455 | -71.0960 | Flag, Green | Search Sector Bravo HQ. Team leader: Davis. Covers N quadrant. |
| 4 | ICS COMMAND POST | 42.4320 | -71.1250 | Building | ICS HQ. Bellevue Pond Parking. Contact: Capt. Lee 617-555-0142 |
| 5 | HELICOPTER LZ NORTH | 42.4530 | -71.1100 | Airport | LZ NORTH. Cleared 40x40m. Approach from S. No obstacles. |
| 6 | MEDICAL STAGING | 42.4335 | -71.1230 | Medical Facility | EMS staging. 2 AMBs on standby. Contact: Medic-1 617-555-0199 |

### Routes (2 total)
| # | Route Name | Waypoints in Order |
|---|------------|-------------------|
| 1 | ALPHA SEARCH ROUTE | ICS COMMAND POST → LKP - HAWTHORN RD → CP-ALPHA → CP-BRAVO → ICS COMMAND POST |
| 2 | BRAVO SEARCH ROUTE | ICS COMMAND POST → MEDICAL STAGING → LKP - HAWTHORN RD → HELICOPTER LZ NORTH → CP-BRAVO → ICS COMMAND POST |

### Export
`File → Export → Export 'My Collection'... → GPX → Desktop\SAR_Middlesex_Fells_2024.gpx`

## Verification
`verifier.py::verify_sar_search_plan` — parses the exported GPX and checks:
- GPX file exists and was created after task start (mandatory gate)
- All 6 waypoints present by name
- Both routes present with correct waypoint ordering
- Key symbols set (ICS = Building, LZ = Airport)
- LKP waypoint has a comment/description set

## Scoring (100 pts, pass ≥ 60)
| Criterion | Points |
|-----------|--------|
| GPX exists + is new | Gate (0 if fails) |
| 6 waypoints × 7 pts | 42 |
| Route ALPHA found | 8 |
| Route ALPHA correct order | 12 |
| Route BRAVO found | 8 |
| Route BRAVO correct order | 12 |
| ICS COMMAND POST symbol = Building | 8 |
| HELICOPTER LZ NORTH symbol = Airport | 5 |
| LKP has comment set | 5 |
| **Total** | **100** |

## Real Data Sources
- **Middlesex Fells Reservation**: Real public open-space area in Middlesex County, MA
- **Coordinates**: Real geographic locations within the Fells reservation boundary
- **Terrain data**: fells_loop.gpx — real GPS track from ExpertGPS (topografix.com), restored into BaseCamp at task start
