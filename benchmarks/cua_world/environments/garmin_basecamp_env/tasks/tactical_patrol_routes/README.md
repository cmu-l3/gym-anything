# Tactical Patrol Routes — Garmin BaseCamp Task

## Overview
**Difficulty**: Very Hard
**Occupation**: Police Tactical Operations Planner / SWAT Commander
**Industry**: Law Enforcement / Public Safety
**Timeout**: 720 s | **Max Steps**: 110

## Scenario
A regional SWAT unit is preparing GPS data for a field training exercise in an urban
park environment. The tactical planner must build a complete GPS package: seven tactical
waypoints (patrol base, objectives, rally points, medevac LZ, blocking position) with
correct symbols and operational comments, plus three routes (primary assault, alternate
assault, exfil), exported as GPX for team leaders' handheld devices.

## Task Requirements

### Waypoints (7 total — all created from scratch in empty BaseCamp)
| # | Name | Lat | Lon | Symbol | Comment |
|---|------|-----|-----|--------|---------|
| 1 | PATROL BASE FOXTROT | 42.4450 | -71.1120 | Flag, Blue | PB FOXTROT. Main staging. Post-op debrief here. |
| 2 | OBJ ALPHA TARGET | 42.4540 | -71.0980 | Flag, Red | PRIMARY OBJ ALPHA. Approach from SE. Evacuate 100m. |
| 3 | OBJ BRAVO COMMS | 42.4380 | -71.0920 | Flag, Red | SECONDARY OBJ BRAVO. Comms relay. Team 2 only. |
| 4 | RP1 CHECKPOINT IRON | 42.4480 | -71.1060 | Waypoint | Rally Point 1 IRON. Hold-short. Confirm comms. |
| 5 | RP2 CHECKPOINT STEEL | 42.4420 | -71.1000 | Waypoint | Rally Point 2 STEEL. Medevac LZ 200m NE. |
| 6 | LZ YANKEE MEDEVAC | 42.4360 | -71.1040 | Airport | LZ YANKEE. 60x60m clear. Medevac ETA 8 min. |
| 7 | BP NORTH BLOCK | 42.4590 | -71.0870 | Flag, Green | Blocking Position NORTH. Prevent exfil N axis. |

### Routes (3 total)
| # | Route Name | Waypoints in Order |
|---|------------|-------------------|
| 1 | ROUTE BLACK PRIMARY | PATROL BASE FOXTROT → RP1 CHECKPOINT IRON → OBJ ALPHA TARGET → RP2 CHECKPOINT STEEL → PATROL BASE FOXTROT |
| 2 | ROUTE RED ALTERNATE | PATROL BASE FOXTROT → OBJ BRAVO COMMS → RP2 CHECKPOINT STEEL → OBJ ALPHA TARGET → RP1 CHECKPOINT IRON → PATROL BASE FOXTROT |
| 3 | ROUTE GREEN EXFIL | OBJ ALPHA TARGET → LZ YANKEE MEDEVAC → BP NORTH BLOCK → PATROL BASE FOXTROT |

### Export
`File → Export → Export 'My Collection'... → GPX → Desktop\TacOp_Exercise_Foxtrot.gpx`

## Scoring (100 pts, pass ≥ 60)
| Criterion | Points |
|-----------|--------|
| GPX exists + is new | Gate |
| 7 waypoints × 6 pts | 42 |
| Route BLACK found | 6 |
| Route BLACK correct order | 6 |
| Route RED found | 8 |
| Route RED correct order | 8 |
| Route GREEN found | 6 |
| Route GREEN correct order | 6 |
| PATROL BASE FOXTROT = Flag, Blue | 5 |
| OBJ ALPHA TARGET = Flag, Red | 5 |
| LZ YANKEE MEDEVAC = Airport | 8 |
| **Total** | **100** |

## Real Data Sources
- **Geographic area**: Middlesex Fells Reservation area coordinates (real public land, MA)
  used as a training exercise environment (standard practice for law enforcement exercises)
- **Waypoint coordinates**: Real geographic positions within the Middlesex Fells area
