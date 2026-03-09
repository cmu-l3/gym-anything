# Race Course Certification — Garmin BaseCamp Task

## Overview
**Difficulty**: Very Hard
**Occupation**: Race Director / Event Operations Manager
**Industry**: Sports Events / Outdoor Recreation
**Timeout**: 720 s | **Max Steps**: 110

## Scenario
The Fells 25K Trail Race needs its official GPS data package built in Garmin BaseCamp.
Eight waypoints (start/finish, aid stations, crew access, medical, mandatory checkpoint)
with specific symbols and operational notes, plus the 9-waypoint official course route,
must be created and exported as GPX for distribution to timing crews and medical staff.

## Task Requirements

### Waypoints (8 total — create in My Collection)
| # | Name | Lat | Lon | Symbol | Comment |
|---|------|-----|-----|--------|---------|
| 1 | START - BELLEVUE POND | 42.4325 | -71.1295 | Flag, Blue | Official Start/Finish. Timing chip mat at 0.0km and 25.0km. Bag check closes 07:45. |
| 2 | AS1 - NORTH LOOP | 42.4495 | -71.1240 | Food/Water | Aid Station 1. Km 7.2. Water, electrolytes, fruit. NO crew access. |
| 3 | AS2 - SHEEPFOLD NORTH | 42.4530 | -71.1020 | Food/Water | Aid Station 2. Km 12.8. Drop bags allowed. Crew OK via Sheepfold Rd. |
| 4 | AS3 - SOUTH FELLS | 42.4240 | -71.1050 | Food/Water | Aid Station 3. Km 19.3. Water, gels, broth. NO crew access. |
| 5 | MANDATORY CP | 42.4460 | -71.1055 | Danger | MANDATORY CHECKPOINT. Km 15.4. Cutoff: 4h30m from start. MUST CHECK IN. |
| 6 | CREW ACCESS A | 42.4355 | -71.1250 | Car | Crew Access Point A. Parking on West St. Runners enter from S only. |
| 7 | CREW ACCESS B | 42.4218 | -71.1140 | Car | Crew Access Point B. Parking off Ravine Rd. No road crossings during race. |
| 8 | MEDICAL CP | 42.4270 | -71.1080 | Medical Facility | Race Medical. Km 21.0. ALS crew on site 07:00-17:00 race day. AED on site. |

### Route (1 total)
**FELLS 25K OFFICIAL COURSE**: START - BELLEVUE POND → AS1 - NORTH LOOP → AS2 - SHEEPFOLD NORTH → MANDATORY CP → AS3 - SOUTH FELLS → CREW ACCESS B → MEDICAL CP → CREW ACCESS A → START - BELLEVUE POND

### Export
`File → Export → Export 'My Collection'... → GPX → Desktop\Fells25K_Official_Course_2024.gpx`

## Scoring (100 pts, pass ≥ 60)
| Criterion | Points |
|-----------|--------|
| GPX exists + is new | Gate (0 if fails) |
| 8 waypoints × 5 pts | 40 |
| Route found | 10 |
| Route 9-point correct order | 25 |
| START symbol = Flag, Blue | 5 |
| 3 aid stations have Food/Water | 10 |
| MANDATORY CP symbol = Danger | 5 |
| MEDICAL CP symbol = Medical Facility | 5 |
| **Total** | **100** |

## Real Data Sources
- **Middlesex Fells Reservation**: Real public park in Middlesex County, MA, USA
- **Trail coordinates**: Real geographic locations within the reservation
- **fells_loop.gpx**: Real GPS data from ExpertGPS/topografix.com
