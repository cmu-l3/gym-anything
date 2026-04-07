# food_pasteurization_tags

## Overview

**Environment**: crimson_env (Red Lion Crimson 3.0, Windows 11)
**Difficulty**: very_hard
**Occupation**: Food Safety Engineer / Quality Assurance Engineer
**Industry**: Food Manufacturing / Dairy Processing
**Standard**: FDA Grade A Pasteurized Milk Ordinance (PMO) 2023 / 21 CFR Part 131
**Archetype**: Implement from Specification

A dairy processing company is commissioning SCADA for a new HTST (High Temperature Short Time) pasteurization line. The agent, acting as the food safety engineer responsible for FDA regulatory compliance, must configure all Critical Control Point (CCP) monitoring tags in Crimson per FDA PMO and 21 CFR Part 131. Both reference documents (CCP tag register and FDA PMO critical limits) are seeded on the Desktop.

---

## Goal

Configure 5 CCP monitoring tags in Crimson's Data Tags section with the correct data type, engineering range (min/max), engineering unit label, description, and alarm thresholds per FDA PMO specifications. Save the project as `food_pasteurization.c3`.

**Critical note**: The alarm thresholds for TT_501 (HTST Holder Temperature) include the FDA PMO critical limit of 161°F, which is a regulatory minimum. Accuracy is essential.

---

## Reference Documents (seeded by setup_task.ps1)

| File | Location | Content |
|------|----------|---------|
| `food_pasteurization_tag_register.csv` | `C:\Users\Docker\Desktop\CrimsonTasks\` | CCP tag names, descriptions, data types, units, engineering ranges |
| `fda_pmo_pasteurization_limits.txt` | `C:\Users\Docker\Desktop\CrimsonTasks\` | FDA PMO critical limits, alarm thresholds, and engineering unit label text |

---

## Required Tags (Ground Truth)

| TagName | Description | DataType | Min | Max | Label | AlarmLow | AlarmHigh |
|---------|-------------|----------|-----|-----|-------|----------|-----------|
| TT_501 | HTST Holder Temperature - CCP1 | Float | 140.0 | 200.0 | Degrees Fahrenheit | 161.0 | 185.0 |
| FT_501 | HTST Forward Flow Rate | Float | 0.0 | 500.0 | Gallons per Minute | 5.0 | 300.0 |
| PT_501 | Pasteurized Product Pressure | Float | 0.0 | 100.0 | Pounds per Square Inch | 1.0 | 80.0 |
| TT_502 | Regeneration Balance Temperature | Float | 100.0 | 200.0 | Degrees Fahrenheit | 130.0 | 185.0 |
| FQ_501 | Daily Batch Total Volume | Float | 0.0 | 999999.0 | Gallons | 0.0 | 900000.0 |

Sources: FDA Grade A PMO 2023 (Section 7 — HTST pasteurizer requirements), 21 CFR Part 131 (Milk and Cream), HTST pasteurizer engineering standards.

---

## Scoring (100 pts total)

| Subtask | Points | Criterion |
|---------|--------|-----------|
| S1 — Tag Presence & Naming | 25 pts (5/tag) | All 5 tag names created exactly |
| S2 — Data Type = Float | 20 pts (4/tag) | Treat As = Float for each tag |
| S3 — Min/Max Ranges | 30 pts (3 per limit) | Engineering range within 2% tolerance |
| S4 — Engineering Unit Label | 25 pts (5/tag) | Label text matches PMO document exactly |

**Pass threshold**: 70 / 100
**Project save**: `C:\Users\Docker\Documents\CrimsonProjects\food_pasteurization.c3`

---

## Verification Strategy

The `export_result.ps1` post-task hook exports tags to CSV and writes `food_pasteurization_result.json`.
The `verifier.py` function `verify_food_pasteurization_tags`:
- **GATE 1**: project_found=false → score=0
- **GATE 2**: No required tags found → score=0 (wrong-target)
- Scores S1–S4 for the 5 CCP tags

---

## Anti-Gaming Properties

- **Do-nothing**: No project → score=0
- **Wrong tag names**: Wrong-target gate → score=0
- **Partial credit**: Each tag and subtask scored independently
- **TT_501 criticality**: Alarm Low of 161.0°F is the FDA PMO critical limit — incorrect value earns no min points for that tag
