# Task: Satellite Classification Audit and Module Reorganization

## Domain Context

Amateur radio clubs and satellite tracking organizations sometimes inherit poorly maintained GPredict configurations where satellites have been placed in incorrect tracking modules. A satellite operations administrator must perform an audit — examining each module's contents, identifying misclassified satellites by their names and orbital characteristics, and correcting the organization. This requires both domain knowledge (knowing which satellites belong to which category) and multi-feature GPredict proficiency.

This task reflects real administrative work at an amateur radio organization or university astronomy club: auditing and correcting a legacy satellite tracking configuration.

## Persona

Satellite Operations Administrator, Amateur Radio Satellite Corporation (AMSAT) Regional Coordinator — responsible for maintaining accurate tracking software configurations for a network of ground stations. Has inherited a misconfigured system and must identify and correct organizational errors.

## Scenario (Very Hard — No UI Hints)

The Amateur module in GPredict has been contaminated with non-amateur satellites that a previous operator added by mistake. Specifically, four polar-orbiting weather satellites were added to the Amateur module where they do not belong. The administrator must:
1. Examine the Amateur module to identify which satellites are weather satellites (not amateur radio satellites)
2. Remove the weather satellites from the Amateur module
3. Create a new "WeatherSats" module containing those weather satellites
4. Add a ground station for the organization's receive facility in Fairbanks, Alaska
5. Enable metric units for professional meteorological compatibility

The difficulty: the agent is not told WHICH satellites in the Amateur module are the misplaced ones — it must inspect the module contents and use satellite naming knowledge to identify the weather satellites among the amateur satellites.

## Task Description (for agent — VERY HARD, goal-only)

You have inherited a GPredict installation that was not properly maintained. The **Amateur** module currently contains some satellites that do not belong there — non-amateur satellites have been mixed in with the real amateur satellites.

Your job:
1. Examine the Amateur module and identify which satellites are **weather/meteorological satellites** (not amateur radio satellites). Remove those misplaced weather satellites from the Amateur module.
2. Create a new module called **WeatherSats** and add those identified weather satellites to it.
3. Add a ground station for the organization's Fairbanks, AK receive facility: Latitude = 64.8378°N, Longitude = 147.7164°W, Altitude = 133 meters.
4. Configure GPredict to use **metric units** for all measurements.

Login: username `ga`, password `password123`. GPredict is already open.

**Note**: You will need to inspect the Amateur module's satellite list to identify which ones are weather satellites versus amateur radio satellites. Weather satellites typically have names like NOAA, FENGYUN, DMSP, SUOMI, METEOSAT, GOES, or similar meteorological agency names.

## What Was Pre-Seeded (for task creator reference — NOT revealed to agent)

The setup script inserts 4 weather satellite NORAD IDs into Amateur.mod:
- SUOMI NPP (37849)
- FENGYUN 3A (32958)
- FENGYUN 3B (37214)
- DMSP 5D-3 F18 / USA 210 (35951)

These are identifiable by name in GPredict's satellite database (they appear as "SUOMI NPP", "FENGYUN 3A", "FENGYUN 3B", "DMSP 5D-3 F18"). The agent must spot these among the legitimate amateur satellites and reclassify them.

## Success Criteria

- Amateur.mod does NOT contain NORAD IDs 37849, 32958, 37214, 35951
- A WeatherSats module exists containing all 4 of those IDs
- Fairbanks.qth exists with correct coordinates (LAT≈64.84, LON≈-147.72, ALT≈133m)
- Metric units enabled in preferences

## Verification Strategy

Scoring (100 points, pass ≥ 60 — lower threshold reflects the discovery difficulty):
- Weather satellites removed from Amateur module (10 pts each × 4): 40 pts
- WeatherSats module contains all 4 weather satellites (10 pts each × 4): 40 pts (partial credit per satellite)
- Fairbanks AK ground station correct: 15 pts
- Metric units enabled: 5 pts

Note: This task has a lower pass threshold (60 pts) because discovery is genuinely hard — an agent that identifies and moves 3 of 4 weather satellites deserves credit.

## Key Data for Verifier

### Weather satellites injected into Amateur.mod
| Satellite | NORAD ID | Recognizable by name |
|-----------|----------|---------------------|
| SUOMI NPP | 37849 | "SUOMI NPP" |
| FENGYUN 3A | 32958 | "FENGYUN 3A" |
| FENGYUN 3B | 37214 | "FENGYUN 3B" |
| DMSP 5D-3 F18 (USA 210) | 35951 | "DMSP 5D-3 F18" |

## GPredict File Format Notes
- Amateur module: `~/.config/Gpredict/modules/Amateur.mod`
- WeatherSats module should be: `~/.config/Gpredict/modules/WeatherSats.mod`
- Satellite names are stored in TLE cache files and displayed in GPredict's satellite selector
