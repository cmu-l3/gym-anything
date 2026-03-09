# Task: vfr_navaid_routing

## Domain Context

Avare is an Electronic Flight Bag (EFB) used by private and student pilots for
VFR (Visual Flight Rules) and IFR navigation in the United States. One of its
core features is the Plan screen, which lets a pilot build a flight route from
a departure airport through intermediate navaids and waypoints to a destination.

**Occupation context**: Private pilots (SOC 53-2011) and student pilots rely on
Avare as a free EFB alternative to Garmin Pilot or ForeFlight. Before a VFR
cross-country flight, a pilot must build a route that follows VOR airways or
prominent geographic corridors, adding intermediate navaids to keep within
gliding/communication range of airfields and to track progress en-route.

---

## Task Goal

Build and **save** a complete VFR cross-country flight plan from
**KSFO** (San Francisco International) to **KLAS** (Las Vegas / Harry Reid
International) that includes at least **3 intermediate navaids or airports**
for a total minimum of **5 waypoints**. The chart display must remain on
**VFR Sectional**.

> Very Hard — the description states only the goal. The agent must discover:
> how to open the Plan screen, how to search for airports/navaids and add them,
> how to verify and set the chart type, and how to save the plan to a file.

---

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| KSFO present in any saved plan | 30 | Departure airport |
| KLAS present in any saved plan | 30 | Destination airport |
| ≥ 5 total waypoints in a single plan | 25 | At least 3 intermediate stops |
| Chart type = Sectional (VFR) | 15 | Must not be IFR |
| **Pass threshold** | **76** | Waypoints criterion required |

**Gate**: If no plan file is saved at all, score = 0.

> Threshold 76 prevents passing on KSFO+KLAS+default_Sectional alone (75 pts);
> ≥5 waypoints are required.

---

## Verification Strategy

1. **export_result.sh** runs on the Android device (after force-stopping Avare
   to flush SharedPreferences):
   - Takes a final screenshot.
   - Copies `com.ds.avare_preferences.xml` to `/sdcard/avare_prefs.xml`.
   - Concatenates all `*.csv` files from `/sdcard/avare/Plans/` into
     `/sdcard/avare_plans_combined.txt`.

2. **verifier.py** (`check_vfr_navaid_routing`) runs on the host:
   - Uses `copy_from_env` to pull both files from the device.
   - **Gate**: `avare_plan_count.txt` == 0 → score 0.
   - Checks `KSFO` / `KLAS` membership in the concatenated CSV text.
   - Counts waypoints in each plan section (skipping the header row).
   - Parses SharedPreferences XML for any `<string name="*chart*">` element
     to detect chart type; absent key → default Sectional → 15 pts.

---

## Schema / Data Reference

| File / Path | Description |
|-------------|-------------|
| `/sdcard/avare/Plans/*.csv` | Saved flight plan files; format: header row then one waypoint per line |
| `/data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml` | App settings XML; chart type stored as `<string name="ChartType">Sectional</string>` |
| `/sdcard/avare_prefs.xml` | Copy written by export script |
| `/sdcard/avare_plans_combined.txt` | All plans concatenated, sections delimited by `=== NAME.csv ===` |
| `/sdcard/avare_plan_count.txt` | Number of saved plan files (integer) |

Real airports used:
- **KSFO** — San Francisco International Airport (37.6213°N, 122.3790°W)
- **KLAS** — Harry Reid International, Las Vegas (36.0840°N, 115.1537°W)

---

## Edge Cases

- If the agent saves the plan under a non-standard name, the verifier still
  finds it (it scans all `*.csv` files).
- If Avare has never had the chart-type preference set, the XML element is
  absent; the verifier awards the Sectional points since Sectional is the
  factory default.
- If the agent uses VOR identifiers rather than ICAO codes (e.g., `SFO` for
  KSFO), it will not score those points — the task specifies ICAO codes in the
  description.

---

## Starting State

`setup_task.sh` clears `/sdcard/avare/Plans/*.csv` before the task begins,
ensuring no pre-existing plan can be mistaken for the agent's work.
