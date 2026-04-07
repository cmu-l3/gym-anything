# Task: utility_pole_inspection

**Environment**: `example.qfield_env@0.1`
**Difficulty**: `very_hard`
**Occupation**: Telecommunications Equipment Installers and Repairers (SOC 49-2022.00)

---

## Task Description

A telecom field inspector reviewing 80 real power poles from the Kansas City metro area (sourced from OpenStreetMap) must apply a compound three-criteria lifecycle replacement rule: set `replacement_flag = 'SCHEDULE'` for all poles that simultaneously meet **Wood** material + **pre-2010** installation + **Fair/Poor/Critical** condition rating. Adding `work_order_notes` for flagged poles is also required.

The key difficulty is the three-way AND logic — poles meeting only 1 or 2 criteria must NOT be flagged. The agent cannot rely on any single field as a shortcut.

---

## Real Data Sources

- **OpenStreetMap Overpass API**: `power=pole` and `power=tower` nodes in Kansas City metro (bbox: 38.85–39.35°N, 94.75–94.25°W), 9,962 OSM features returned; 80 selected
- **Industry standard**: ANSI O5.1 / utility asset lifecycle policies for wood pole replacement

---

## GeoPackage Structure

**File**: `utility_pole_inspection.gpkg`
**Layer**: `pole_inventory` (Point, EPSG:4326)

| Column | Type | Notes |
|--------|------|-------|
| fid | INTEGER PK | |
| geom | BLOB | Point geometry |
| pole_id | TEXT | Company ID (KCP-XXXXX) |
| osm_id | TEXT | OSM node ID |
| material | TEXT | Wood / Concrete / Steel / Fiberglass |
| install_year | INTEGER | Year of installation |
| height_m | REAL | Pole height in meters |
| condition_rating | TEXT | Good / Fair / Poor / Critical |
| last_inspection_date | TEXT | ISO date |
| inspector_id | TEXT | |
| circuit_id | TEXT | |
| replacement_flag | TEXT | **Target field** — start: OK |
| work_order_notes | TEXT | **Target field** — must explain criteria |
| photo_ref | TEXT | |

**Replacement criteria** (ALL three must be true):
1. `material = 'Wood'`
2. `install_year < 2010`
3. `condition_rating IN ('Fair', 'Poor', 'Critical')`

**~13 poles** meet all three criteria simultaneously.

---

## Setup / Post-Task

- `setup_task.sh`: Copies GeoPackage to QField's writable directory, launches via VIEW intent
- `post_task.sh`: Force-stops QField, copies result to `/sdcard/utility_pole_inspection_result.gpkg`

---

## Verification Logic (`verifier.py::check_utility_pole_inspection`)

Scoring (100 pts total):
- 5 pts per correctly flagged SCHEDULE pole (~13 poles × 5 = **65 pts**)
- 2 pts per non-empty `work_order_notes` for SCHEDULE pole
- **−4 pts**: per false positive (OK pole incorrectly flagged SCHEDULE)
- **+15 pts precision bonus**: if 0 false positives AND ≥10 correctly flagged

**Pass threshold: 60**

Do-nothing score: **0** (all poles remain OK)

---

## Expected Agent Workflow

1. Open `pole_inventory` layer → see KC metro pole map
2. Browse attributes → identify poles with material=Wood, install_year<2010, condition in {Fair, Poor, Critical}
3. Enable edit mode → flag qualifying poles, add work_order_notes
4. Verify non-qualifying poles are not changed
5. Save all edits

**Ideal path**: ~40–50 steps
**max_steps**: 80 | **timeout_sec**: 640

---

## Antipattern Check

- ✅ All poles start as OK (no free points)
- ✅ False positive penalty for over-flagging
- ✅ Three-way AND prevents shortcut strategies (can't just flag all Wood poles)
- ✅ Do-nothing score = 0 < pass threshold of 60
