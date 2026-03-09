# Offshore Passage Plan — Garmin BaseCamp Task

## Overview
**Difficulty**: Very Hard
**Occupation**: Offshore Sailing Navigator / Yacht Racing Captain
**Industry**: Maritime Navigation / Competitive Offshore Sailing
**Timeout**: 900 s | **Max Steps**: 120

## Scenario
Preparing the GPS passage plan for a racing yacht competing in the Newport Bermuda Race
(635 nautical miles). The navigator must enter ten waypoints (rhumb-line route waypoints
plus two emergency diversion ports), assign marine-appropriate symbols with operational
notes, build both a primary rhumb-line route and a weather-diversion alternate route,
and export the complete plan as GPX for upload to the yacht's chartplotter.

## Real Data Sources
- **Newport Bermuda Race**: Real annual offshore yacht race since 1906 (newportbermuda.com)
- **Brenton Reef**: 41.4901°N, 71.3128°W — actual race start area, Brenton Reef Lighted Buoy R"2"
- **Nantucket Lightship Float**: 41.2539°N, 69.9921°W — real danger waypoint S of Cape Cod
- **Georges Bank SE**: 40.5000°N, 67.0000°W — real fishing bank waypoint
- **Gulf Stream**: 38-36°N, 65-66°W — real Gulf Stream crossing zone
- **St. David's Head**: 32.3682°N, 64.6515°W — actual finish mark, St. David's Head Light
- **Halifax NS**: 44.6476°N, 63.5752°W — Halifax Harbour, Nova Scotia
- **Ponta Delgada, Azores**: 37.7412°N, 25.6756°W — real port of Ponta Delgada

## Task Requirements

### Waypoints (10 total)
| # | Name | Lat | Lon | Symbol |
|---|------|-----|-----|--------|
| 1 | BRENTON REEF WHISTLE | 41.4901 | -71.3128 | Buoy, White |
| 2 | NANTUCKET LS FLOAT | 41.2539 | -69.9921 | Buoy, White |
| 3 | GEORGES BANK SE | 40.5000 | -67.0000 | Waypoint |
| 4 | GULF STREAM ENTRY | 38.8000 | -66.5000 | Danger |
| 5 | GULF STREAM EXIT | 36.5000 | -65.8000 | Danger |
| 6 | BERMUDA APPROACH N | 33.2000 | -64.9000 | Waypoint |
| 7 | NORTH ROCK BUOY | 32.4985 | -64.8024 | Buoy, White |
| 8 | ST. DAVIDS HEAD FINISH | 32.3682 | -64.6515 | Flag, Blue |
| 9 | EMERGENCY - HALIFAX NS | 44.6476 | -63.5752 | Medical Facility |
| 10 | EMERGENCY - AZORES | 37.7412 | -25.6756 | Medical Facility |

### Routes (2 total)
- **NEWPORT BERMUDA 2024 RHUMB**: BRENTON REEF → NANTUCKET → GEORGES BANK SE → GS ENTRY → GS EXIT → BDA APPROACH → N ROCK → ST. DAVIDS
- **NEWPORT BERMUDA 2024 WEATHER ALT**: BRENTON REEF → NANTUCKET → EMERGENCY HALIFAX → GS ENTRY → GS EXIT → BDA APPROACH → N ROCK → ST. DAVIDS

### Export
`File → Export → Export 'My Collection'... → GPX → Desktop\Newport_Bermuda_2024_PassagePlan.gpx`

## Scoring (100 pts, pass ≥ 60)
| Criterion | Points |
|-----------|--------|
| GPX exists + is new | Gate |
| 10 waypoints × 5 pts | 50 |
| Rhumb route found | 6 |
| Rhumb route correct 8-point order | 10 |
| Weather alt route found | 6 |
| Weather alt correct 8-point order | 8 |
| BRENTON REEF symbol = Buoy, White | 5 |
| ST. DAVIDS HEAD symbol = Flag, Blue | 5 |
| Both EMERGENCY = Medical Facility | 5 |
| Both Gulf Stream = Danger | 5 |
| **Total** | **100** |
