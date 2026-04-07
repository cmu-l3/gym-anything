# Task: forest_stand_reinventory

**Environment**: `example.qfield_env@0.1`
**Difficulty**: `very_hard`
**Occupation**: Forest and Conservation Workers (SOC 45-4011.00)

---

## Task Description

A USFS forest inventory technician identifies stands overdue for reinventory (≥5 years since last inventory, using 2024-07-01 as reference) on the Chequamegon-Nicolet National Forest in Wisconsin. For each overdue stand, the agent must:
1. Update `reinventory_status` from `CURRENT` to `OVERDUE`
2. Add `field_notes` with the years-overdue count
3. Set `priority_rank` (1 = overdue >7 years, 2 = overdue 5–7 years)
4. Insert at least one tree measurement record into the linked `tree_measurements` table

This is the most complex task in the set — it requires reasoning about dates, writing to two tables, and applying forest inventory domain knowledge.

---

## Real Data Sources

- **USFS FIA (Forest Inventory and Analysis) DataMart**: 30 real FIA plot locations from the Chequamegon-Nicolet National Forest, Wisconsin (coordinates jittered to ±0.01° per FIA privacy policy). Real plot IDs (WI-5401 through WI-5430), real forest types, real inventory date distributions.

---

## GeoPackage Structure

**File**: `forest_stand_reinventory.gpkg`

### Table: `forest_stands` (Point, EPSG:4326)

| Column | Type | Notes |
|--------|------|-------|
| fid | INTEGER PK | |
| geom | BLOB | Point geometry |
| stand_id | TEXT | e.g. FS-WI-5403-2018 |
| fia_plot_id | TEXT | FIA plot identifier |
| forest_type | TEXT | Aspen/Birch, Northern Hardwood, Spruce/Fir, Jack Pine, Red Pine |
| canopy_cover_pct | INTEGER | |
| basal_area_sq_ft_per_acre | REAL | |
| stand_condition | TEXT | Good / Fair / Poor |
| last_inventory_date | TEXT | ISO date (year is key) |
| next_due_date | TEXT | last_inventory + 5 years |
| crew_id | TEXT | |
| reinventory_status | TEXT | **Target field** — start: CURRENT |
| field_notes | TEXT | **Target field** — years overdue |
| priority_rank | INTEGER | **Target field** — 1 or 2 |

### Table: `tree_measurements`

| Column | Type | Notes |
|--------|------|-------|
| mid | INTEGER PK | |
| stand_fid | INTEGER | FK to forest_stands.fid |
| stand_id | TEXT | |
| tree_tag | TEXT | e.g. T-0003-001 |
| species_code | TEXT | USFS species code |
| dbh_inches | REAL | |
| total_height_ft | REAL | |
| crown_class | TEXT | |
| condition_code | TEXT | |
| azimuth_deg | INTEGER | |
| distance_ft | REAL | |
| measured_date | TEXT | |
| crew_member | TEXT | |

**Overdue stands** (last_inventory_date ≤ 2019, i.e., ≥5 years before 2024-07-01): **14 of 30 stands**

Species codes by forest_type:
- Aspen/Birch → `POTR5` (*Populus tremuloides*)
- Spruce/Fir → `ABBA` (*Abies balsamea*)
- Northern Hardwood → `ACSA3` (*Acer saccharum*)
- Red Pine → `PIRE` (*Pinus resinosa*)
- Jack Pine → `PIBA2` (*Pinus banksiana*)

---

## Setup / Post-Task

- `setup_task.sh`: Copies GeoPackage to QField's writable directory, launches via VIEW intent
- `post_task.sh`: Force-stops QField, copies result to `/sdcard/forest_stand_reinventory_result.gpkg`

---

## Verification Logic (`verifier.py::check_forest_stand_reinventory`)

Scoring (100 pts total):
- 4 pts × 14 = **56 pts**: each overdue stand correctly set to OVERDUE
- 1 pt × 14 = **14 pts**: non-empty `field_notes` per OVERDUE stand
- 1 pt × 14 = **14 pts**: correct `priority_rank` (1 or 2)
- 1 pt per stand (cap 14) = **14 pts**: at least 1 `tree_measurements` row for each OVERDUE stand
- **−4 pts**: per false positive (CURRENT stand incorrectly marked OVERDUE)

**Pass threshold: 60**

Do-nothing score: **0** (all stands remain CURRENT, no tree measurements)

---

## Expected Agent Workflow

1. Open `forest_stands` layer → see FIA plot map of northern Wisconsin
2. Browse stands → find `last_inventory_date` for each → compute years since 2024-07-01
3. Identify stands with ≥5 years since last inventory
4. Enable edit mode → update `reinventory_status`, `field_notes`, `priority_rank` for overdue stands
5. Switch to `tree_measurements` layer → add at least one measurement per overdue stand
6. Save all edits

**Ideal path**: ~50–60 steps (complex two-table task)
**max_steps**: 100 | **timeout_sec**: 800

---

## Antipattern Check

- ✅ All stands start as CURRENT (no free points)
- ✅ False positive penalty prevents blanket-updating all stands
- ✅ Two-table requirement tests understanding of relational GIS data
- ✅ Priority rank requires computing exact years overdue (not just binary old/new)
- ✅ Do-nothing score = 0 < pass threshold of 60
- ✅ Tree measurements table starts empty — cannot trivially pass absence check
