# Task: ifr_transcontinental_routing

## Domain Context

Commercial airline dispatchers and long-haul flight crews file IFR
transcontinental flight plans across the continental US. For flights at
enroute altitudes below FL180, the **IFR Low-Altitude Enroute chart** is the
standard reference, displaying Victor airways, MEAs, VORs, and compulsory
reporting points.

**Occupation context**: Airline dispatchers (SOC 53-2031) and instrument-rated
pilots use EFB software to draft routing from a west-coast hub to an east-coast
hub before filing with FAA. A typical KLAX→KJFK routing crosses the Southwest,
Rocky Mountains, Great Plains, and Appalachians via a sequence of VOR fixes.

This task requires the agent to:
- Switch to the correct IFR chart type.
- Build a long-haul multi-waypoint plan.
- Save it persistently.

---

## Task Goal

1. **Switch the chart to IFR Low-Altitude Enroute** display.
2. **Build and save a flight plan** with **KLAX** (Los Angeles International)
   as departure and **KJFK** (John F. Kennedy International) as destination,
   including at least **4 intermediate waypoints** (navaids, fixes, or airports)
   for a **total minimum of 6 waypoints**.

The routing must follow a plausible east-bound path across the continental US.
No specific waypoints are required — only the count and the endpoints.

> Very Hard — the agent must navigate the Plan screen, search and add multiple
> intermediate waypoints, switch the chart type, and save.

---

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| Chart = IFR Low-Altitude (GATE on score) | 25 | SharedPreferences check |
| KLAX in any saved plan | 25 | Departure |
| KJFK in any saved plan | 25 | Destination |
| ≥ 6 waypoints in a single plan | 25 | 4 intermediate required |
| **Pass threshold** | **76** | Any 3-of-4 = max 75; all 4 required |

**Gate**: If no plan file is saved, score = 0.

> Threshold 76 ensures no 3-of-4 combination reaches passing; all four
> criteria must be met.

---

## Verification Strategy

1. **export_result.sh** (Android device):
   - Takes final screenshot.
   - Force-stops Avare.
   - Copies SharedPreferences XML → `/sdcard/avare_trans_prefs.xml`.
   - Collects all plan CSVs → `/sdcard/avare_trans_plans.txt`.

2. **verifier.py** (`check_ifr_transcontinental_routing`) (host):
   - Pulls both files via `copy_from_env`.
   - **Gate**: plan count == 0 → score 0.
   - Parses SharedPreferences for IFR Low chart preference.
   - Checks plan text for `KLAX` and `KJFK`.
   - Counts waypoints in each plan section; awards 25 pts if max ≥ 6.

---

## Schema / Data Reference

| File / Path | Description |
|-------------|-------------|
| `/sdcard/avare_trans_prefs.xml` | SharedPreferences copy |
| `/sdcard/avare_trans_plans.txt` | All plan CSVs concatenated |
| `/sdcard/avare_trans_plan_count.txt` | Number of plan files |

Real airports:
- **KLAX** — Los Angeles International (33.9425°N, 118.4081°W)
- **KJFK** — John F. Kennedy International, New York (40.6413°N, 73.7781°W)

---

## Starting State

`setup_task.sh` clears all existing plan files and attempts to set the chart
to Sectional in SharedPreferences, so the agent must explicitly switch to
IFR Low.

---

## Edge Cases

- Waypoints may be VOR identifiers (3-letter, e.g., `TUS`, `ELP`, `SAT`),
  airport ICAO codes (4-letter, e.g., `KTUS`), or named fixes. The verifier
  counts all non-header non-blank lines — it is not restricted to ICAO codes.
- If the agent saves multiple partial plans, only the longest single plan
  counts for the waypoint criterion.
