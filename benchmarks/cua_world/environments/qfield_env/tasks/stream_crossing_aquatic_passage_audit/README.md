# Task: stream_crossing_aquatic_passage_audit

**Environment**: `example.qfield_env@0.1`
**Difficulty**: `very_hard`
**Occupation**: Forest and Conservation Workers (SOC 45-4011.00)

---

## Task Description

A fish passage specialist must conduct an aquatic organism passage (AOP) compliance audit for the Willamette National Forest road system in Oregon. A previous inspection team incorrectly recorded some stream crossings as `PASSING` despite their physical dimensions violating USFS AOP design criteria required for anadromous and resident fish movement. The specialist must apply USFS and ODFW passage standards to identify non-compliant crossings and update their status accordingly.

The agent receives **no explicit hints** about which crossings are miscoded or which thresholds apply — domain knowledge of fish passage engineering is required.

---

## Real Data Sources

- **Willamette National Forest road network**: Real stream crossing locations from OSM Overpass API (Willamette NF, OR) with fallback to known culvert/bridge coordinates
- **USFS Aquatic Organism Passage Design Guide 2021**: Federal passage criteria for culverts and bridges on National Forest roads
- **ODFW (Oregon Department of Fish and Wildlife) passage criteria**: State-level passage standards for anadromous salmon and steelhead

---

## AOP Passage Criteria (USFS / ODFW)

| Parameter | Threshold | Action |
|-----------|-----------|--------|
| outlet_drop_cm | > 12.0 cm | Outlet drop barrier for juvenile salmonids |
| outlet_width / bankfull_width | < 0.8 | Hydraulic constriction — passage barrier |
| slope_pct | > 10.0% | Steep slope — velocity barrier |
| structure_type | `perched_culvert` or `box_culvert_undersized` | Known barrier structure types |
| substrate_type | `concrete_smooth` or `metal_smooth` | Impassable smooth substrate |

---

## GeoPackage Structure

**File**: `stream_crossing_aquatic_passage_audit.gpkg`
**Layer**: `stream_crossings` (Point, EPSG:4326)

| Column | Type | Notes |
|--------|------|-------|
| fid | INTEGER PK | |
| geom | BLOB | Point geometry |
| crossing_id | TEXT | Crossing site identifier |
| stream_name | TEXT | Stream name |
| road_id | TEXT | Forest road number |
| structure_type | TEXT | culvert / bridge / perched_culvert / box_culvert_undersized |
| substrate_type | TEXT | native_bed / concrete_smooth / metal_smooth / rock |
| outlet_drop_cm | REAL | Outlet elevation drop (cm) |
| outlet_width_m | REAL | Outlet width (m) |
| bankfull_width_m | REAL | Bankfull channel width (m) |
| slope_pct | REAL | Channel slope (%) |
| inspection_date | TEXT | ISO date |
| inspector_id | TEXT | Field crew identifier |
| aop_status | TEXT | **Target field** — some seeded as PASSING incorrectly |
| passage_barrier_note | TEXT | **Target field** — must describe the specific barrier criterion |
| remediation_priority | TEXT | |

---

## Seeded Errors (agent must find and fix)

| Crossing ID | Failing Parameter | Value | Threshold |
|-------------|-------------------|-------|-----------|
| WNF-XR-001 | outlet_drop_cm | 18.5 cm | > 12 cm |
| WNF-XR-002 | outlet_w/bankfull | 1.4/2.2 = 0.64 | < 0.8 |
| WNF-XR-003 | slope_pct | 13.5% | > 10% |
| WNF-XR-004 | structure_type | perched_culvert | barrier structure |
| WNF-XR-005 | substrate_type | concrete_smooth | barrier substrate |
| WNF-XR-006 | outlet_drop_cm | 20.0 cm | > 12 cm |
| WNF-XR-007 | outlet_w/bankfull | 1.0/2.8 = 0.36 | < 0.8 |
| WNF-XR-008 | slope_pct | 15.0% | > 10% |
| WNF-XR-009 | structure_type | box_culvert_undersized | barrier structure |
| WNF-XR-010 | substrate_type | metal_smooth | barrier substrate |
| WNF-XR-011 | outlet_drop_cm | 22.0 cm | > 12 cm |
| WNF-XR-012 | outlet_w/bankfull | 0.9/2.5 = 0.36 | < 0.8 |

Background sites (35 total): all measurements within AOP criteria → should remain `PASSING`

---

## Setup Script Behavior (`setup_task.sh`)

1. Force-stops QField
2. Copies `stream_crossing_aquatic_passage_audit.gpkg` from `/sdcard/QFieldData/` to `/sdcard/Android/data/ch.opengis.qfield/files/` (writable)
3. Launches QField via `VIEW` intent
4. Waits for QField to fully load

---

## Post-Task Script (`post_task.sh`)

1. Force-stops QField (checkpoints SQLite WAL)
2. Copies the modified GeoPackage to `/sdcard/stream_crossing_aquatic_passage_audit_result.gpkg`

---

## Verification Logic (`verifier.py::check_stream_crossing_aquatic_passage_audit`)

Scoring (100 pts total):
- 6 pts × 12 = **72 pts**: each non-compliant crossing's `aop_status` changed to `FAILING`
- 1 pt × 12 = **12 pts**: each site has a non-empty `passage_barrier_note`
- **−5 pts** per false positive (background crossing wrongly changed when it meets all AOP criteria)
- **+16 pts** bonus: all 12 corrected with zero false positives

**Pass threshold: 60**

### Strategy Enumeration (Anti-Pattern 13 check)

| Strategy | Score | Pass? |
|----------|-------|-------|
| Do-nothing | 0 | No |
| Mass-action (change all 47 to FAILING) | 12×7 − 35×5 = 84 − 175 = **0** (clamped) | No ✓ |
| Partial correct (5/12) | 5×7 = **35** | No ✓ |
| Full correct (12/12 + bonus) | 12×7 + 16 = **100** | Yes ✓ |

---

## Expected Agent Workflow

1. Open QField → `stream_crossings` layer (map of Willamette NF stream crossings)
2. Tap features → inspect `outlet_drop_cm`, `outlet_width_m`, `bankfull_width_m`, `slope_pct`, `structure_type`, `substrate_type`
3. Compute width ratio (outlet_width / bankfull_width) and compare against AOP thresholds
4. Enable edit mode → open each non-compliant crossing → change `aop_status` to `FAILING` → add `passage_barrier_note`
5. Save all edits

**Ideal path**: ~60–70 steps (12 sites × ~5 steps each + navigation overhead)
**max_steps**: 75 | **timeout_sec**: 600

---

## Antipattern Check

- ✅ No baseline recording needed (checking specific field values, not counts)
- ✅ Target fields reset: non-compliant crossings seeded with `aop_status='PASSING'`
- ✅ Do-nothing score = 0 < pass threshold 60
- ✅ Mass-action score = 0 (heavy false positive penalty: 35 background sites × 5 pts = 175 pts penalty)
- ✅ Real Willamette NF stream crossing locations from OSM
