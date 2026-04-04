# CRISPR Knockout Screen Documentation

## Task Overview

**Difficulty**: very_hard
**Domain**: Molecular Biology / Genomics Research
**Occupation Context**: Molecular and Cellular Biologists (top SciNote user occupation by economic importance)

This task requires documenting a complete CRISPR knockout screen workflow in SciNote ELN from scratch. The agent must understand how SciNote's project/experiment/task hierarchy works, create workflow connections between tasks, add protocol steps, and build a reagent inventory — without being given UI navigation instructions.

---

## Goal

Set up complete ELN documentation for a pooled CRISPR knockout screen targeting KRAS-pathway genes in HCT116 cells:

**Project**: `CRISPR Knockout Screen - KRAS`

**Experiment 1**: `sgRNA Library Synthesis`
- Tasks (in order): `Oligo Design and Ordering` → `PCR Amplification` → `Library Cloning`
- All three tasks must be connected with workflow arrows

**Experiment 2**: `Cell Line Engineering`
- Tasks (in order): `Lentiviral Production` → `Cell Transduction and Selection`
- Both tasks must be connected

**Protocol**: Add ≥6 steps to the `Lentiviral Production` task (standard lentiviral production: plasmid prep, transfection, harvest, titration, etc.)

**Inventory**: Create `CRISPR Screen Reagents` with 4 columns: `Supplier`, `Catalog Number`, `Concentration`, `Storage Temperature`. Add items: `Cas9 Protein (SpCas9)`, `sgRNA Library (Pooled)`, `Polybrene`

---

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Project found | 10 | Project name matches exactly |
| sgRNA Library Synthesis experiment | 10 | Experiment exists in correct project |
| Cell Line Engineering experiment | 10 | Experiment exists in correct project |
| 3 tasks in sgRNA experiment | 15 | Oligo Design, PCR Amplification, Library Cloning (5 pts each) |
| 2 tasks in Cell Line experiment | 10 | Lentiviral Production, Cell Transduction (5 pts each) |
| Connection: Oligo → PCR | 10 | Sequential workflow arrow |
| Connection: PCR → Library Cloning | 10 | Sequential workflow arrow |
| Connection: Lenti → Transduction | 5 | Sequential workflow arrow |
| Protocol ≥6 steps | 10 | Steps in Lentiviral Production task |
| Inventory found | 5 | CRISPR Screen Reagents inventory exists |
| Inventory ≥4 columns | 5 | Supplier, Catalog Number, Concentration, Storage Temperature |

**Pass threshold**: 60/100

---

## Starting State

Blank SciNote instance — no pre-seeded data. Agent must create everything from scratch.

---

## Verification Strategy

`export_result.sh` queries:
- `projects` table for project by name
- `experiments` table for experiments by project_id and name pattern
- `my_modules` table for tasks by experiment_id and name pattern
- `connections` table for specific task-to-task connections (output_id → input_id)
- `protocols` and `steps` tables for protocol step count
- `repositories` and `repository_columns` tables for inventory

`verifier.py` uses fuzzy pattern matching (LIKE queries via LOWER()) to tolerate minor name variations.

---

## Database Schema Reference

```sql
-- Projects
SELECT id, name FROM projects WHERE name = 'CRISPR Knockout Screen - KRAS';

-- Experiments
SELECT id, name FROM experiments WHERE project_id = ? AND name LIKE '%sgrna%library%synth%';

-- Tasks (my_modules)
SELECT id, name FROM my_modules WHERE experiment_id = ? AND name LIKE '%lentiviral%prod%';

-- Connections (output_id = predecessor, input_id = successor)
SELECT COUNT(*) FROM connections WHERE output_id = ? AND input_id = ?;

-- Protocol steps
SELECT COUNT(*) FROM steps WHERE protocol_id = (SELECT id FROM protocols WHERE my_module_id = ?);

-- Inventory columns
SELECT name FROM repository_columns WHERE repository_id = ?;
```

---

## Edge Cases

- Task names with minor spelling variations are tolerated (LIKE pattern matching)
- Connections must be in the correct direction (predecessor → successor)
- Archived tasks are excluded from counts
- Inventory column count check is ≥4 (not exact) to allow for variations
