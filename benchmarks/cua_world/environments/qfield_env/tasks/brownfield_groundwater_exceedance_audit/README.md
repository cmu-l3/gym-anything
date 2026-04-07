# Task: brownfield_groundwater_exceedance_audit

**Environment**: `example.qfield_env@0.1`
**Difficulty**: `very_hard`
**Occupation**: Environmental Science and Protection Technicians, Including Health (SOC 19-4042.00)

---

## Task Description

An environmental science technician must conduct a groundwater compliance review at a brownfield Superfund site in Gary, Indiana. Laboratory analytical results from monitoring wells sampled under the CERCLA remediation program contain a data quality error — some wells were recorded as `BELOW_CLEANUP_LEVEL` when their contaminant concentrations actually exceed EPA Maximum Contaminant Levels (MCLs) established under 40 CFR Part 141 and applicable CERCLA cleanup standards. The technician must compare each well's contaminant concentrations against EPA MCL values and update the compliance status accordingly.

The agent receives **no explicit hints** about which wells are miscoded or which MCL thresholds apply — domain knowledge of environmental remediation chemistry is required.

---

## Real Data Sources

- **Gary, Indiana Superfund area**: Real monitoring well locations based on the EPA CERCLA brownfield site area near Gary, IN (Lake County), an industrial brownfield area with historical VOC and heavy metal contamination
- **EPA MCL 40 CFR Part 141**: Federal Maximum Contaminant Levels for drinking water contaminants
- **CERCLA cleanup standards**: EPA-mandated remediation targets for Superfund site groundwater

---

## EPA MCL Thresholds (40 CFR Part 141)

| Contaminant | MCL | Action |
|-------------|-----|--------|
| TCE (trichloroethylene) | 5.0 µg/L | Exceeds MCL — EXCEEDS_CLEANUP_LEVEL |
| PCE (tetrachloroethylene) | 5.0 µg/L | Exceeds MCL — EXCEEDS_CLEANUP_LEVEL |
| Benzene | 5.0 µg/L | Exceeds MCL — EXCEEDS_CLEANUP_LEVEL |
| Arsenic | 10.0 µg/L | Exceeds MCL — EXCEEDS_CLEANUP_LEVEL |
| Lead | 15.0 µg/L | Exceeds MCL — EXCEEDS_CLEANUP_LEVEL |
| Vinyl chloride | 2.0 µg/L | Exceeds MCL — EXCEEDS_CLEANUP_LEVEL |
| 1,2-DCE (dichloroethylene) | 70.0 µg/L | Exceeds MCL — EXCEEDS_CLEANUP_LEVEL |

---

## GeoPackage Structure

**File**: `brownfield_groundwater_exceedance_audit.gpkg`
**Layer**: `monitoring_wells` (Point, EPSG:4326)

| Column | Type | Notes |
|--------|------|-------|
| fid | INTEGER PK | |
| geom | BLOB | Point geometry |
| well_id | TEXT | Monitoring well identifier |
| site_name | TEXT | Superfund site name |
| county | TEXT | Lake County, IN |
| install_date | TEXT | ISO date |
| well_depth_m | REAL | Screened interval depth (m) |
| sample_date | TEXT | ISO date |
| lab_id | TEXT | Certified laboratory identifier |
| TCE_ug_L | REAL | Trichloroethylene (µg/L) |
| PCE_ug_L | REAL | Tetrachloroethylene (µg/L) |
| benzene_ug_L | REAL | Benzene (µg/L) |
| arsenic_ug_L | REAL | Arsenic (µg/L) |
| lead_ug_L | REAL | Lead (µg/L) |
| vinyl_chloride_ug_L | REAL | Vinyl chloride (µg/L) |
| DCE_ug_L | REAL | 1,2-Dichloroethylene (µg/L) |
| compliance_status | TEXT | **Target field** — some seeded as BELOW_CLEANUP_LEVEL incorrectly |
| exceedance_note | TEXT | **Target field** — must identify contaminant and exceedance amount |
| next_sample_date | TEXT | |

---

## Seeded Errors (agent must find and fix)

| Well ID | Failing Contaminant | Value | MCL |
|---------|---------------------|-------|-----|
| MW-001 | TCE | 8.5 µg/L | 5.0 µg/L |
| MW-002 | PCE | 7.8 µg/L | 5.0 µg/L |
| MW-003 | Benzene | 8.9 µg/L | 5.0 µg/L |
| MW-004 | Arsenic | 14.5 µg/L | 10.0 µg/L |
| MW-005 | Lead | 22.0 µg/L | 15.0 µg/L |
| MW-006 | TCE | 6.2 µg/L | 5.0 µg/L |
| MW-007 | Vinyl chloride | 3.5 µg/L | 2.0 µg/L |
| MW-008 | PCE + 1,2-DCE | PCE=6.4 + DCE=85.0 µg/L | both exceed MCL |
| MW-009 | TCE | 9.8 µg/L | 5.0 µg/L |
| MW-010 | Benzene | 6.7 µg/L | 5.0 µg/L |
| MW-011 | Arsenic | 11.5 µg/L | 10.0 µg/L |

Background wells (30 total): all contaminants below EPA MCL → should remain `BELOW_CLEANUP_LEVEL`

---

## Setup Script Behavior (`setup_task.sh`)

1. Force-stops QField
2. Copies `brownfield_groundwater_exceedance_audit.gpkg` from `/sdcard/QFieldData/` to `/sdcard/Android/data/ch.opengis.qfield/files/` (writable)
3. Launches QField via `VIEW` intent
4. Waits for QField to fully load

---

## Post-Task Script (`post_task.sh`)

1. Force-stops QField (checkpoints SQLite WAL)
2. Copies the modified GeoPackage to `/sdcard/brownfield_groundwater_exceedance_audit_result.gpkg`

---

## Verification Logic (`verifier.py::check_brownfield_groundwater_exceedance_audit`)

Scoring (100 pts total):
- 7 pts × 11 = **77 pts**: each exceedance well's `compliance_status` changed to `EXCEEDS_CLEANUP_LEVEL`
- 1 pt × 11 = **11 pts**: each well has a non-empty `exceedance_note`
- **−6 pts** per false positive (below-MCL well wrongly changed)
- **+12 pts** bonus: all 11 corrected with zero false positives

**Pass threshold: 60**

### Strategy Enumeration (Anti-Pattern 13 check)

| Strategy | Score | Pass? |
|----------|-------|-------|
| Do-nothing | 0 | No |
| Mass-action (change all 41 to EXCEEDS_CLEANUP_LEVEL) | 11×8 − 30×6 = 88 − 180 = **0** (clamped) | No ✓ |
| Partial correct (5/11) | 5×8 = **40** | No ✓ |
| Full correct (11/11 + bonus) | 11×8 + 12 = **100** | Yes ✓ |

---

## Expected Agent Workflow

1. Open QField → `monitoring_wells` layer (map of Gary IN Superfund site monitoring wells)
2. Tap features → inspect `TCE_ug_L`, `PCE_ug_L`, `benzene_ug_L`, `arsenic_ug_L`, `lead_ug_L`, `vinyl_chloride_ug_L`, `DCE_ug_L`
3. Apply EPA MCL thresholds (40 CFR Part 141) from domain knowledge
4. Enable edit mode → open each exceedance well → change `compliance_status` to `EXCEEDS_CLEANUP_LEVEL` → add `exceedance_note` identifying the specific contaminant(s) and exceedance amount
5. Save all edits

**Ideal path**: ~55–65 steps (11 sites × ~5 steps each + navigation overhead)
**max_steps**: 75 | **timeout_sec**: 600

---

## Antipattern Check

- ✅ No baseline recording needed (checking specific field values, not counts)
- ✅ Target fields reset: exceedance wells seeded with `compliance_status='BELOW_CLEANUP_LEVEL'`
- ✅ Do-nothing score = 0 < pass threshold 60
- ✅ Mass-action score = 0 (30 background wells × 6 pts = 180 pts penalty far exceeds 88 pts max gain)
- ✅ Real Gary IN brownfield area locations based on EPA CERCLA Superfund site data
