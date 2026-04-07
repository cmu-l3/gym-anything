# Task: crop_pest_scouting

**Environment**: `example.qfield_env@0.1`
**Difficulty**: `very_hard`
**Occupation**: Farmworkers and Laborers, Crop, Nursery, and Greenhouse (SOC 45-2092.00)

---

## Task Description

An agricultural field scout reviews 62 Iowa crop field zones and must apply University of Iowa Extension IPM (Integrated Pest Management) economic thresholds to determine which zones require treatment. The agent sets `treatment_recommendation = 'TREAT'` for zones where any pest count exceeds threshold, adds `action_notes` explaining which pest exceeded, and fills `recheck_date` (7 days after `scout_date`).

The difficulty lies in: (1) knowing the thresholds independently, (2) checking 5 different pest counts per zone, and (3) filling 3 fields correctly for TREAT zones while leaving MONITOR zones unchanged.

---

## Real Data Sources

- **USDA NASS / Iowa county areas**: Iowa county polygons used as scouting zone boundaries with real geographic coordinates
- **University of Iowa Extension IPM Thresholds**: Published economic thresholds for corn and soybean pests (publicly available at extension.iastate.edu)

---

## GeoPackage Structure

**File**: `crop_pest_scouting.gpkg`
**Layer**: `scout_zones` (Polygon, EPSG:4326)

| Column | Type | Notes |
|--------|------|-------|
| fid | INTEGER PK | |
| geom | BLOB | Polygon geometry (~1 sq mile field zone) |
| zone_id | TEXT | e.g. IA-STO-19169-Z01 |
| county | TEXT | Iowa county name |
| fips_code | INTEGER | County FIPS |
| crop_type | TEXT | Corn or Soybean |
| growth_stage | TEXT | V6, R1, etc. |
| field_acres | REAL | Approximate acreage |
| scout_date | TEXT | ISO date |
| scout_id | TEXT | Scout identifier |
| soybean_aphid_per_plant | REAL | Count |
| corn_rootworm_beetles_per_trap | REAL | Count |
| corn_borer_egg_masses_per_100 | REAL | Count |
| bean_leaf_beetle_per_sweep | REAL | Count |
| defoliation_pct | REAL | Percentage |
| treatment_recommendation | TEXT | **Target field** — start: MONITOR |
| action_notes | TEXT | **Target field** — must name pest and count |
| recheck_date | TEXT | **Target field** — 7 days after scout_date |

**IPM Economic Thresholds** (agent must know):

| Pest | Threshold |
|------|-----------|
| Soybean aphid | > 250 per plant |
| Corn rootworm beetles | > 5 per trap/day |
| European corn borer egg masses | > 10 per 100 plants |
| Bean leaf beetle | > 8 per sweep-net pass |
| Defoliation | > 20% pre-bloom |

**10 zones** exceed at least one threshold.

---

## Setup / Post-Task

- `setup_task.sh`: Copies GeoPackage to QField's writable directory, launches via VIEW intent
- `post_task.sh`: Force-stops QField, copies result to `/sdcard/crop_pest_scouting_result.gpkg`

---

## Verification Logic (`verifier.py::check_crop_pest_scouting`)

Scoring (100 pts total):
- 6 pts × 10 = **60 pts**: each zone correctly set to TREAT
- 2 pts × 10 = **20 pts**: non-empty `action_notes` per TREAT zone
- 1 pt × 10 = **10 pts**: `recheck_date` within 3–14 days of `scout_date`
- **−4 pts**: per false positive (MONITOR zone incorrectly set TREAT)
- **+10 pts precision bonus**: if 0 false positives AND ≥8 correct TREAT

**Pass threshold: 60**

Do-nothing score: **0** (all zones remain MONITOR)

---

## Expected Agent Workflow

1. Open `scout_zones` layer → see Iowa field polygon map
2. Browse polygon attributes → check all 5 pest count fields per zone
3. Compare counts against IPM thresholds (agent must know or look up)
4. Enable edit mode → update `treatment_recommendation`, `action_notes`, `recheck_date` for exceeding zones
5. Save all edits

**Ideal path**: ~45–50 steps
**max_steps**: 80 | **timeout_sec**: 640

---

## Antipattern Check

- ✅ All zones start as MONITOR (no free points)
- ✅ False positive penalty prevents flagging all zones
- ✅ 5 independent threshold checks — cannot rely on single field shortcut
- ✅ Three required fields per TREAT zone (recommendation + notes + date)
- ✅ Do-nothing score = 0 < pass threshold of 60
