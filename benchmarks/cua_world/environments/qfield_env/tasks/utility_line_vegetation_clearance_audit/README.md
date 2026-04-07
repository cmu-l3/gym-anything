# Task: utility_line_vegetation_clearance_audit

**Environment**: `example.qfield_env@0.1`
**Difficulty**: `very_hard`
**Occupation**: Tree Trimmers and Pruners (SOC 37-3013.00)

---

## Task Description

A certified arborist must conduct a NERC FAC-003-4 vegetation management compliance audit for a utility company in the Nashville, Tennessee service territory. A vegetation management contractor incorrectly recorded some trees as `COMPLIANT` without properly applying NERC FAC-003-4 and ANSI A300 Part 7 clearance standards. The arborist must evaluate each tree's measurements against the applicable clearance criteria and identify trees that require trimming.

The agent receives **no explicit hints** about which trees are miscoded or which thresholds apply — domain knowledge of utility arboriculture and NERC vegetation standards is required.

---

## Real Data Sources

- **Nashville TN urban tree canopy**: Real street tree locations from OSM Overpass API (Nashville, TN metro) with fallback to known coordinates near utility corridors
- **NERC FAC-003-4 Transmission Vegetation Management Standard**: Federal reliability standard for maintaining clearances between vegetation and overhead transmission lines
- **ANSI A300 Part 7 (Integrated Vegetation Management)**: Professional standard for utility vegetation management practices

---

## Clearance Criteria (NERC FAC-003-4 / ANSI A300 Part 7)

| Criterion | Threshold | Action |
|-----------|-----------|--------|
| Zone 1 encroachment | distance_to_conductor_m < 3.05 m (10 ft) | TRIM_REQUIRED — immediate clearance zone |
| Grow-in violation | height_m > (conductor_height_m − 3.0 m) | TRIM_REQUIRED — tree will grow into conductor |
| Fall-in risk | lean_toward_line=1 AND height_m > distance_to_conductor_m × 1.2 | TRIM_REQUIRED — leaning tree fall hazard |

---

## GeoPackage Structure

**File**: `utility_line_vegetation_clearance_audit.gpkg`
**Layer**: `vegetation_survey` (Point, EPSG:4326)

| Column | Type | Notes |
|--------|------|-------|
| fid | INTEGER PK | |
| geom | BLOB | Point geometry |
| tree_id | TEXT | Tree survey identifier |
| species | TEXT | Tree species (common name) |
| circuit_id | TEXT | Utility circuit/feeder identifier |
| survey_date | TEXT | ISO date |
| crew_id | TEXT | Survey crew identifier |
| height_m | REAL | Tree height (m) |
| conductor_height_m | REAL | Overhead conductor height (m) |
| distance_to_conductor_m | REAL | Horizontal distance to nearest conductor (m) |
| lean_toward_line | INTEGER | 1 = leaning toward line, 0 = upright/away |
| dbh_cm | REAL | Diameter at breast height (cm) |
| clearance_status | TEXT | **Target field** — some seeded as COMPLIANT incorrectly |
| trim_reason | TEXT | **Target field** — must specify which NERC/ANSI criterion applies |
| next_inspection_date | TEXT | |

---

## Seeded Errors (agent must find and fix)

| Tree ID | Failing Criterion | Details | Threshold |
|---------|-------------------|---------|-----------|
| VEG-001 | Zone 1 encroachment | dist=1.5 m | < 3.05 m |
| VEG-002 | Grow-in violation | height=14.5 m > conductor 12.0 − 3.0 = 9.0 m | height > cond_h − 3 |
| VEG-003 | Zone 1 encroachment | dist=2.8 m | < 3.05 m |
| VEG-004 | Fall-in risk | lean=1, height=12.5 m > 9.0×1.2=10.8 m | height > dist × 1.2 |
| VEG-005 | Zone 1 encroachment | dist=2.1 m | < 3.05 m |
| VEG-006 | Grow-in violation | height=15.0 m > conductor 12.0 − 3.0 = 9.0 m | height > cond_h − 3 |
| VEG-007 | Fall-in risk | lean=1, height=11.5 m > 8.5×1.2=10.2 m | height > dist × 1.2 |
| VEG-008 | Zone 1 encroachment | dist=2.5 m | < 3.05 m |
| VEG-009 | Grow-in violation | height=14.2 m > conductor 11.0 − 3.0 = 8.0 m | height > cond_h − 3 |
| VEG-010 | Fall-in risk | lean=1, height=10.8 m > 7.8×1.2=9.36 m | height > dist × 1.2 |

Background trees (40 total): all measurements within NERC clearance standards → should remain `COMPLIANT`

---

## Setup Script Behavior (`setup_task.sh`)

1. Force-stops QField
2. Copies `utility_line_vegetation_clearance_audit.gpkg` from `/sdcard/QFieldData/` to `/sdcard/Android/data/ch.opengis.qfield/files/` (writable)
3. Launches QField via `VIEW` intent
4. Waits for QField to fully load

---

## Post-Task Script (`post_task.sh`)

1. Force-stops QField (checkpoints SQLite WAL)
2. Copies the modified GeoPackage to `/sdcard/utility_line_vegetation_clearance_audit_result.gpkg`

---

## Verification Logic (`verifier.py::check_utility_line_vegetation_clearance_audit`)

Scoring (100 pts total):
- 8 pts × 10 = **80 pts**: each non-compliant tree's `clearance_status` changed to `TRIM_REQUIRED`
- 1 pt × 10 = **10 pts**: each tree has a non-empty `trim_reason`
- **−6 pts** per false positive (background tree wrongly changed when it meets all clearance standards)
- **+10 pts** bonus: all 10 corrected with zero false positives

**Pass threshold: 60**

### Strategy Enumeration (Anti-Pattern 13 check)

| Strategy | Score | Pass? |
|----------|-------|-------|
| Do-nothing | 0 | No |
| Mass-action (change all 50 to TRIM_REQUIRED) | 10×9 − 40×6 = 90 − 240 = **0** (clamped) | No ✓ |
| Partial correct (5/10) | 5×9 = **45** | No ✓ |
| Full correct (10/10 + bonus) | 10×9 + 10 = **100** | Yes ✓ |

---

## Expected Agent Workflow

1. Open QField → `vegetation_survey` layer (map of Nashville TN trees near power lines)
2. Tap features → inspect `height_m`, `conductor_height_m`, `distance_to_conductor_m`, `lean_toward_line`
3. Apply NERC FAC-003-4 Zone 1 / grow-in / fall-in criteria from domain knowledge
4. Enable edit mode → open each failing tree → change `clearance_status` to `TRIM_REQUIRED` → add `trim_reason`
5. Save all edits

**Ideal path**: ~50–60 steps (10 sites × ~5 steps each + navigation overhead)
**max_steps**: 75 | **timeout_sec**: 600

---

## Antipattern Check

- ✅ No baseline recording needed (checking specific field values, not counts)
- ✅ Target fields reset: non-compliant trees seeded with `clearance_status='COMPLIANT'`
- ✅ Do-nothing score = 0 < pass threshold 60
- ✅ Mass-action score = 0 (40 background trees × 6 pts = 240 pts penalty far exceeds 90 pts max gain)
- ✅ Real Nashville TN tree locations from OSM
