# GR7 Guided Tour Plan — Garmin BaseCamp Task

## Overview
**Difficulty**: Very Hard
**Occupation**: Grande Randonnée Trail Guide / Tour Operator
**Industry**: Outdoor Tourism / Long-Distance Trail Management (France)
**Timeout**: 720 s | **Max Steps**: 110

## Scenario
A licensed GR trail guide is preparing GPS data for a 5-day guided hiking tour from
Dole to Langres on the GR7 long-distance trail (~124 km, Burgundy/Franche-Comté, France).
The agent must import the existing track GPX, create 7 waypoints for daily stages
(departure, lunch stops, overnight accommodation, resupply), build the 7-point guided
itinerary route, and export everything as GPX for participant devices.

## Real Data Sources
- **GR7 (Grande Randonnée 7)**: Real long-distance hiking trail maintained by the
  Fédération Française de la Randonnée Pédestre (FFRandonnée)
- **Dole (Jura)**: 47.0930°N, 5.4962°E — real city and SNCF train station
- **Pesmes**: 47.2770°N, 5.5620°E — real medieval village on the Ognon river
- **Gray (Haute-Saône)**: 47.4490°N, 5.5970°E — real city on the Saône river
- **Champlitte**: 47.6183°N, 5.5133°E — real village, Musée des Arts et Traditions Populaires
- **Jussey**: 47.8247°N, 5.9046°E — real village in Haute-Saône
- **Langres**: 47.8620°N, 5.3344°E — real fortified city, UNESCO ramparts, end of GR7 section
- **Track file**: dole_langres_track.gpx — real GPS track of the Dole-Langres GR7 section

## Task Requirements

### Step 1 — Import
Import `dole_langres_track.gpx` from the Desktop: `File → Import...`

### Step 2 — Waypoints (7 total)
| # | Name | Lat | Lon | Symbol |
|---|------|-----|-----|--------|
| 1 | DEPART DOLE GARE | 47.0930 | 5.4962 | Car |
| 2 | REPAS LABERGEMENT | 47.1640 | 5.5100 | Picnic Area |
| 3 | NUIT 1 PESMES | 47.2770 | 5.5620 | Building |
| 4 | NUIT 2 GRAY | 47.4490 | 5.5970 | Building |
| 5 | RAVITAILLEMENT CHAMPLITTE | 47.6183 | 5.5133 | Food/Water |
| 6 | NUIT 3 JUSSEY | 47.8247 | 5.9046 | Building |
| 7 | ARRIVEE LANGRES | 47.8620 | 5.3344 | Flag, Blue |

### Step 3 — Route
**GR7 DOLE-LANGRES 5 JOURS**: DEPART DOLE GARE → REPAS LABERGEMENT → NUIT 1 PESMES → NUIT 2 GRAY → RAVITAILLEMENT CHAMPLITTE → NUIT 3 JUSSEY → ARRIVEE LANGRES

### Step 4 — Export
`File → Export → Export 'My Collection'... → GPX → Desktop\GR7_Guide_DoleLangres.gpx`

## Scoring (100 pts, pass ≥ 60)
| Criterion | Points |
|-----------|--------|
| GPX exists + is new | Gate |
| Track imported (≥1 track in GPX) | 10 |
| 7 waypoints × 7 pts | 49 |
| Route found | 10 |
| Route 7-point correct order | 15 |
| DEPART symbol = Car | 5 |
| ARRIVEE symbol = Flag, Blue | 5 |
| 2+ NUIT waypoints = Building | 6 |
| **Total** | **100** |
