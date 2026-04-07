# pharma_bioreactor_tags

## Overview

**Environment**: crimson_env (Red Lion Crimson 3.0, Windows 11)
**Difficulty**: very_hard
**Occupation**: Validation Engineer / Automation Engineer
**Industry**: Pharmaceutical / Biotechnology Manufacturing
**Standard**: FDA 21 CFR Part 211 / ICH Q8(R2) / USP <1058>
**Archetype**: Implement from Specification

A pharmaceutical company is qualifying a GMP-compliant SCADA system for a bioreactor manufacturing suite. The agent, acting as the validation engineer responsible for IQ/OQ documentation, must configure all critical process monitoring tags in Crimson per FDA GMP requirements. Both reference documents (bioreactor tag register and GMP process parameters) are seeded on the Desktop.

---

## Goal

Configure 5 GMP-compliant bioreactor monitoring tags in Crimson's Data Tags section with the correct data type, engineering range (min/max), engineering unit label, description, and alarm thresholds per the regulatory specifications. Save the project as `pharma_bioreactor.c3`.

**Success state**: The saved Crimson project contains all 5 correctly configured GMP tags within 2% tolerance.

---

## Reference Documents (seeded by setup_task.ps1)

| File | Location | Content |
|------|----------|---------|
| `pharma_bioreactor_tag_register.csv` | `C:\Users\Docker\Desktop\CrimsonTasks\` | Tag names, descriptions, data types, units, engineering ranges |
| `fda_gmp_process_parameters.txt` | `C:\Users\Docker\Desktop\CrimsonTasks\` | FDA/ICH/USP alarm thresholds and engineering unit label text |

---

## Required Tags (Ground Truth)

| TagName | Description | DataType | Min | Max | Label | AlarmLow | AlarmHigh |
|---------|-------------|----------|-----|-----|-------|----------|-----------|
| TT_301 | Bioreactor Temperature - Fermentation | Float | 30.0 | 45.0 | Degrees Celsius | 36.0 | 38.0 |
| PH_301 | Bioreactor Process pH | Float | 5.0 | 9.0 | pH Units | 6.80 | 7.40 |
| DO_301 | Dissolved Oxygen - Bioreactor | Float | 0.0 | 100.0 | Percent DO Saturation | 20.0 | 80.0 |
| AS_301 | Agitator Speed - Bioreactor | Float | 0.0 | 1500.0 | Revolutions per Minute | 50.0 | 800.0 |
| PT_301 | Vessel Headspace Pressure | Float | 0.0 | 3.0 | Bar Gauge | 0.0 | 1.50 |

Sources: FDA 21 CFR Part 211 (cGMP for Finished Pharmaceuticals), ICH Q8(R2) Pharmaceutical Development, USP <1058> Analytical Instrument Qualification.

---

## Scoring (100 pts total)

| Subtask | Points | Criterion |
|---------|--------|-----------|
| S1 — Tag Presence & Naming | 25 pts (5/tag) | All 5 tag names created exactly |
| S2 — Data Type = Float | 20 pts (4/tag) | Treat As = Float for each tag |
| S3 — Min/Max Ranges | 30 pts (3 per limit) | Engineering range within 2% tolerance |
| S4 — Engineering Unit Label | 25 pts (5/tag) | Label text matches GMP parameters doc exactly |

**Pass threshold**: 70 / 100
**Project save**: `C:\Users\Docker\Documents\CrimsonProjects\pharma_bioreactor.c3`

---

## Verification Strategy

The `export_result.ps1` post-task hook exports tags to CSV and writes `pharma_bioreactor_result.json`.
The `verifier.py` function `verify_pharma_bioreactor_tags`:
- **GATE 1**: project_found=false → score=0
- **GATE 2**: No required tags found → score=0 (wrong-target)
- Scores S1–S4 for the 5 bioreactor tags

---

## Anti-Gaming Properties

- **Do-nothing**: No project → score=0
- **Wrong tag names**: Wrong-target gate → score=0
- **Partial credit**: Each tag scored independently across all 4 subtasks
