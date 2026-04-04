# ELISA Assay Setup Documentation

## Task Overview

**Difficulty**: hard
**Domain**: Immunology / Bioassay Development
**Occupation Context**: Molecular and Cellular Biologists, Biochemists and Biophysicists

The agent extends a partially set-up ELISA project: creating the experiment structure, building out the workflow, documenting the plate coating protocol, and populating the pre-existing reagent inventory with real antibody data.

---

## Starting State (Pre-seeded by setup_task.sh)

- **Project**: `ELISA Assay Development - IL-6` (created)
- **Inventory**: `ELISA Consumables` (created) with 2 columns: `Supplier`, `Catalog Number` — but **no items**

No experiments, tasks, or protocol steps exist yet.

---

## Goal

1. **Create experiment**: `Antibody Pair Optimization` inside the existing project
2. **Add 4 tasks** in sequential order: `Plate Coating` → `Sample Dilution` → `Primary Antibody Incubation` → `Signal Detection`
3. **Connect all 4 tasks** with workflow arrows in the above order
4. **Add ≥5 protocol steps** to the `Plate Coating` task
5. **Expand inventory**: Add 2 more columns to `ELISA Consumables`: `Volume (mL)` and `Storage Temperature`
6. **Add 3 items** with Supplier and Catalog Number filled in:
   - `IL-6 Capture Antibody` (R&D Systems, MAB206)
   - `IL-6 Detection Antibody` (R&D Systems, BAF206)
   - `Streptavidin-HRP` (R&D Systems, DY998)

---

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Experiment 'Antibody Pair Optimization' | 15 | Created in correct project |
| 4 tasks found | 20 | Plate Coating, Sample Dilution, Primary Ab Incubation, Signal Detection (5 pts each) |
| 3 connections | 15 | Plate Coating→Dilution→Primary Ab→Signal (5 pts each) |
| Protocol ≥5 steps in Plate Coating | 10 | Steps documented |
| Column 'Volume (mL)' added | 5 | New column in ELISA Consumables |
| Column 'Storage Temperature' added | 5 | New column in ELISA Consumables |
| 3 items with catalog numbers | 30 | 5 pts item found + 5 pts correct catalog (×3) |

**Pass threshold**: 60/100

---

## Verification Strategy

`export_result.sh`:
- Finds project `ELISA Assay Development - IL-6` and then experiment within it
- Finds 4 tasks using LIKE patterns
- Checks 3 specific connections (directional)
- Counts steps in Plate Coating's protocol
- Finds inventory by name, checks column names for 'volume' and 'storage' keywords
- Gets items and queries catalog number column

---

## Real Data Used

All catalog numbers are genuine R&D Systems products from their DuoSet ELISA kit for human IL-6:
- MAB206: R&D Systems Mouse Anti-Human IL-6 Capture Antibody
- BAF206: R&D Systems Biotinylated Human IL-6 Detection Antibody
- DY998: R&D Systems Streptavidin-HRP

---

## Edge Cases

- Inventory pre-exists with 2 columns; agent adds 2 more (total ≥4)
- Pre-existing columns (Supplier, Catalog Number) must not be deleted
- Column matching uses grep-qi for 'volume' and 'storage' keywords
- Item name matching is flexible (kw-in-name or name-in-kw)
