# water_treatment_scada_tags

## Overview

**Environment**: crimson_env (Red Lion Crimson 3.0, Windows 11)
**Difficulty**: very_hard
**Occupation**: Process Engineer / Instrumentation Engineer
**Industry**: Municipal Water Treatment
**Standard**: WHO Guidelines for Drinking-water Quality (4th Ed, 2022) / AWWA
**Archetype**: Implement from Specification

A municipal water treatment plant is upgrading its SCADA system. The agent, acting as the process engineer, must configure all required process monitoring data tags in Red Lion Crimson 3.0 per the plant's tag register and WHO/AWWA drinking water quality standards. Both reference documents are seeded on the Desktop by the pre-task hook.

---

## Goal

Configure 5 water quality monitoring tags in Crimson's Data Tags section with the correct data type, engineering range (min/max), engineering unit label, description, and alarm thresholds per the reference specifications. Save the project as `water_treatment.c3`.

**Success state**: The saved Crimson project contains all 5 correctly configured tags matching the specifications within 2% tolerance.

---

## Reference Documents (seeded by setup_task.ps1)

| File | Location | Content |
|------|----------|---------|
| `water_treatment_tag_register.csv` | `C:\Users\Docker\Desktop\CrimsonTasks\` | Tag names, descriptions, data types, engineering units, min/max ranges |
| `who_water_quality_standards.txt` | `C:\Users\Docker\Desktop\CrimsonTasks\` | WHO/AWWA alarm thresholds and engineering unit label text |

---

## Required Tags (Ground Truth)

| TagName | Description | DataType | Min | Max | Label | AlarmLow | AlarmHigh |
|---------|-------------|----------|-----|-----|-------|----------|-----------|
| CT_101 | Free Chlorine Residual - Primary | Float | 0.01 | 8.00 | mg per Liter | 0.20 | 4.00 |
| PH_101 | Process Water pH - Inlet | Float | 4.00 | 11.00 | pH Units | 6.50 | 8.50 |
| TU_101 | Turbidity Sensor - Coagulation Outlet | Float | 0.00 | 25.00 | Nephelometric Turbidity Units | 0.00 | 4.00 |
| TT_101 | Raw Water Inlet Temperature | Float | 0.00 | 40.00 | Degrees Celsius | 1.00 | 32.00 |
| PT_101 | Distribution Pressure Transmitter | Float | 0.00 | 700.00 | Kilopascals | 138.00 | 586.00 |

Sources: WHO GDWQ 4th Ed (2022), AWWA Manual M22 Distribution System Water Quality.

---

## Scoring (100 pts total)

| Subtask | Points | Criterion |
|---------|--------|-----------|
| S1 — Tag Presence & Naming | 25 pts (5/tag) | All 5 tag names created exactly |
| S2 — Data Type = Float | 20 pts (4/tag) | Treat As = Float for each tag |
| S3 — Min/Max Ranges | 30 pts (3 per limit) | Engineering range within 2% tolerance |
| S4 — Engineering Unit Label | 25 pts (5/tag) | Label text matches WHO standards doc exactly |

**Pass threshold**: 70 / 100
**Project save**: `C:\Users\Docker\Documents\CrimsonProjects\water_treatment.c3`

---

## Verification Strategy

The `export_result.ps1` post-task hook:
1. Finds and opens the saved `.c3` project in Crimson
2. Navigates to Data Tags and uses Export Tags to produce a CSV
3. Parses the CSV with flexible column detection
4. Writes `C:\Users\Docker\Desktop\CrimsonTasks\water_treatment_result.json`

The `verifier.py` function `verify_water_treatment_scada_tags`:
- **GATE 1**: project_found=false → score=0 (do-nothing protection)
- **GATE 2**: No required tags found → score=0 (wrong-target protection)
- Scores S1–S4 incrementally; total capped at 100

---

## Anti-Gaming Properties

- **Do-nothing**: No project saved → export returns project_found=false → score=0
- **Wrong target**: Agent configures different tag names → required_upper ∩ exported = ∅ → score=0
- **Partial credit**: Each of the 4 subtasks is independently scored; a partially configured tag earns partial credit

---

## Edge Cases

- The Export Tags CSV column headers vary; the export script uses regex-based column detection
- Engineering ranges with value 0.0 are checked with absolute tolerance (1e-6) to avoid division by zero
- Label comparison is case-insensitive
- If Crimson is not running at export time, the script launches it with the saved project before exporting
