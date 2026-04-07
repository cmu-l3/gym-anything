# datacenter_hvac_tags

## Overview

**Environment**: crimson_env (Red Lion Crimson 3.0, Windows 11)
**Difficulty**: very_hard
**Occupation**: Facilities Engineer / Building Automation Engineer
**Industry**: Commercial Real Estate / Data Center Operations
**Standard**: ASHRAE Standard 90.4-2022 / ASHRAE TC 9.9 / ANSI/BICSI 002-2019
**Archetype**: Implement from Specification

A commercial data center is deploying a new BMS/SCADA system for critical environmental monitoring in its server rooms. The agent, acting as the facilities engineer, must configure all required environmental monitoring tags in Crimson per ASHRAE A2 class data center standards. Both reference documents (tag register and ASHRAE standards specification) are seeded on the Desktop.

---

## Goal

Configure 6 environmental monitoring tags in Crimson's Data Tags section with the correct data type, engineering range (min/max), engineering unit label, description, and alarm thresholds per ASHRAE specifications. Save the project as `datacenter_hvac.c3`.

**Success state**: The saved Crimson project contains all 6 correctly configured HVAC monitoring tags within 2% tolerance.

---

## Reference Documents (seeded by setup_task.ps1)

| File | Location | Content |
|------|----------|---------|
| `datacenter_hvac_tag_register.csv` | `C:\Users\Docker\Desktop\CrimsonTasks\` | Tag names, descriptions, data types, units, engineering ranges |
| `ashrae_datacenter_standards.txt` | `C:\Users\Docker\Desktop\CrimsonTasks\` | ASHRAE TC 9.9 alarm thresholds and engineering unit label text |

---

## Required Tags (Ground Truth)

| TagName | Description | DataType | Min | Max | Label | AlarmLow | AlarmHigh |
|---------|-------------|----------|-----|-----|-------|----------|-----------|
| TT_401 | IT Equipment Inlet Temperature | Float | 0.0 | 50.0 | Degrees Celsius | 10.0 | 35.0 |
| RH_401 | Relative Humidity - IT Room | Float | 0.0 | 100.0 | Percent Relative Humidity | 20.0 | 80.0 |
| DP_401 | Dew Point Temperature - IT Room | Float | -20.0 | 30.0 | Degrees Celsius | -12.0 | 17.0 |
| PT_401 | CRAC Discharge Static Pressure | Float | -2.0 | 2.0 | Inches Water Gauge | 0.0 | 1.5 |
| FT_401 | CRAC Unit Airflow Rate | Float | 0.0 | 10000.0 | Cubic Feet per Minute | 1000.0 | 9000.0 |
| TT_402 | Return Air Temperature - Hot Aisle | Float | 0.0 | 60.0 | Degrees Celsius | 20.0 | 45.0 |

Sources: ASHRAE Standard 90.4-2022 (Energy Standard for Data Centers), ASHRAE TC 9.9 Thermal Guidelines (2021), ANSI/BICSI 002-2019 Data Center Design and Implementation Best Practices.

---

## Scoring (100 pts total)

| Subtask | Points | Criterion |
|---------|--------|-----------|
| S1 — Tag Presence & Naming | 24 pts (4/tag) | All 6 tag names created exactly |
| S2 — Data Type = Float | 18 pts (3/tag) | Treat As = Float for each tag |
| S3 — Min/Max Ranges | 36 pts (3 per limit) | Engineering range within 2% tolerance |
| S4 — Engineering Unit Label | 22 pts (~3-4/tag) | Label text matches ASHRAE standards doc |

**Pass threshold**: 70 / 100
**Project save**: `C:\Users\Docker\Documents\CrimsonProjects\datacenter_hvac.c3`

---

## Verification Strategy

The `export_result.ps1` post-task hook exports tags to CSV and writes `datacenter_hvac_result.json`.
The `verifier.py` function `verify_datacenter_hvac_tags`:
- **GATE 1**: project_found=false → score=0
- **GATE 2**: No required tags found → score=0 (wrong-target)
- Scores S1–S4 for the 6 HVAC tags

---

## Anti-Gaming Properties

- **Do-nothing**: No project → score=0
- **Wrong tag names**: Wrong-target gate → score=0
- **Partial credit**: Each tag and each subtask scored independently
