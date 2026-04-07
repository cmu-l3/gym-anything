# Task: wildlife_species_audit

**Environment**: `example.qfield_env@0.1`
**Difficulty**: `very_hard`
**Occupation**: Zoologists and Wildlife Biologists (SOC 19-1023.00)

---

## Task Description

A wildlife biologist auditing IUCN Red List conservation status codes in a GBIF-derived bird observation dataset for Iowa. The agent must identify which species have incorrect `conservation_status` values, correct them to the IUCN Red List 2023 codes, and add priority notes for all NT/VU/EN/CR species.

The agent receives **zero explicit hints** about which species are wrong or what the correct codes are — domain knowledge of the IUCN Red List is required.

---

## Real Data Sources

- **GBIF API** (`api.gbif.org/v1/occurrence/search`): 64 real bird observations from Iowa, class Aves, 2020–2024, human observations with verified coordinates
- **IUCN Red List 2023**: Publicly known conservation status for Iowa breeding/migrating birds

---

## GeoPackage Structure

**File**: `wildlife_species_audit.gpkg`
**Layer**: `species_observations` (Point, EPSG:4326)

| Column | Type | Notes |
|--------|------|-------|
| fid | INTEGER PK | |
| geom | BLOB | Point geometry |
| species_name | TEXT | Latin binomial |
| common_name | TEXT | English name |
| observation_date | TEXT | ISO date |
| observer | TEXT | |
| gbif_id | TEXT | GBIF occurrence key |
| habitat | TEXT | |
| individual_count | INTEGER | |
| conservation_status | TEXT | **Target field** — some seeded WRONG |
| priority_note | TEXT | **Target field** — must be filled for NT+ |
| verified | INTEGER | 0/1 |

**Seeded errors** (agent must find and fix):

| Species | Wrong (seeded) | Correct (IUCN 2023) |
|---------|---------------|---------------------|
| *Grus americana* | LC | **EN** |
| *Bubo scandiacus* | LC | **VU** |
| *Charadrius melodus* | LC | **NT** |
| *Limosa fedoa* | LC | **NT** |

---

## Setup Script Behavior (`setup_task.sh`)

1. Force-stops QField
2. Copies `wildlife_species_audit.gpkg` from `/sdcard/QFieldData/` to `/sdcard/Android/data/ch.opengis.qfield/files/` (writable)
3. Launches QField via `VIEW` intent pointing at the GeoPackage
4. Waits for QField to fully load (14s nominal)

---

## Post-Task Script (`post_task.sh`)

1. Force-stops QField (checkpoints SQLite WAL)
2. Copies the modified GeoPackage to `/sdcard/wildlife_species_audit_result.gpkg`
3. Verifier reads from `/sdcard/wildlife_species_audit_result.gpkg` via `copy_from_env`

---

## Verification Logic (`verifier.py::check_wildlife_species_audit`)

Scoring (100 pts total):
- 15 pts × 4 = **60 pts**: each correctly updated `conservation_status`
- 10 pts × 4 = **40 pts**: each non-empty `priority_note` for that species

**Pass threshold: 60** (agent must get all 4 statuses correct)

False positives (changing a correct status) are not directly penalized but do not earn points.

Do-nothing score: **0** (all 4 wrong statuses remain LC, no notes filled)

---

## Expected Agent Workflow

1. Open QField → see `species_observations` layer loaded (map of Iowa bird points)
2. Browse feature attributes → inspect `conservation_status` and `species_name` for each record
3. Use domain knowledge to identify which statuses are wrong (requires IUCN Red List 2023 knowledge)
4. Enable edit mode → open each wrong-status record → update `conservation_status` → add `priority_note`
5. Save all edits

**Ideal path**: ~30–35 steps (4 records × ~7 steps each: tap feature → open edit → change status → add note → save)

**max_steps**: 75 | **timeout_sec**: 600

---

## Antipattern Check

- ✅ No baseline recording needed (checking specific field values, not counts)
- ✅ Target fields reset to wrong values in setup (conservation_status = 'LC' for all 4 targets)
- ✅ Do-nothing score = 0 < pass threshold of 60
- ✅ Cannot accidentally pass with empty GeoPackage (requires specific matching species)
