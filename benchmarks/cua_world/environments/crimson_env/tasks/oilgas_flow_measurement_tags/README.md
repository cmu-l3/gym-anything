# oilgas_flow_measurement_tags

## Overview

**Environment**: crimson_env (Red Lion Crimson 3.0, Windows 11)
**Difficulty**: very_hard
**Occupation**: SCADA Automation Engineer
**Industry**: Oil and Gas — Upstream/Midstream
**Standard**: AGA Report No. 3 (2012) / API MPMS Chapter 14.3 / OSHA 29 CFR 1910.1000
**Archetype**: Batch with Judgment

A natural gas production company is commissioning SCADA for wellsite W-201. The agent must configure the *active* measurement tags for this wellsite. The tag register lists 8 tags total — 6 active (W-201) and 2 inactive (W-202). The agent must read the register to identify which tags are in service at W-201 and configure only those. Configuring the inactive W-202 tags (FT_202, PT_202) is a disqualifying error that returns score=0.

---

## Goal

Configure 6 active W-201 measurement tags in Crimson per AGA-3/API flow measurement standards. Each active tag must have the correct data type, engineering range, unit label, description, and alarm thresholds. Save the project as `oilgas_flow.c3`.

**Do NOT configure**: FT_202 or PT_202 (inactive, belong to wellsite W-202).

---

## Reference Documents (seeded by setup_task.ps1)

| File | Location | Content |
|------|----------|---------|
| `oilgas_wellsite_tag_register.csv` | `C:\Users\Docker\Desktop\CrimsonTasks\` | 8 tags with TagName, Description, DataType, Unit, Min, Max, Wellsite, **Status** |
| `aga3_measurement_parameters.txt` | `C:\Users\Docker\Desktop\CrimsonTasks\` | AGA-3/API/OSHA alarm thresholds and engineering unit label text |

---

## Required Tags — Active W-201 Only (Ground Truth)

| TagName | Description | DataType | Min | Max | Label | AlarmLow | AlarmHigh |
|---------|-------------|----------|-----|-----|-------|----------|-----------|
| FT_201 | Gas Flow Rate - AGA-3 Orifice Meter | Float | 0.0 | 10.0 | Million Std Cubic Feet per Day | 0.5 | 8.5 |
| PT_201 | Upstream Static Pressure - Meter Run | Float | 0.0 | 1500.0 | Pounds per Sq Inch Absolute | 200.0 | 1200.0 |
| TT_201 | Gas Temperature - AGA-3 Meter Run | Float | -40.0 | 200.0 | Degrees Fahrenheit | 10.0 | 130.0 |
| DP_201 | Differential Pressure - Orifice Plate | Float | 0.0 | 250.0 | Inches Water Column | 0.0 | 200.0 |
| AT_201 | Hydrogen Sulfide Concentration - Safety | Float | 0.0 | 100.0 | Parts per Million | 0.0 | 10.0 |
| FQ_201 | Cumulative Gas Volume - Daily Total | Float | 0.0 | 999999.0 | Thousand Standard Cubic Feet | 0.0 | 500000.0 |

**Inactive tags (must NOT be configured)**:

| TagName | Wellsite | Status |
|---------|----------|--------|
| FT_202 | W-202 | INACTIVE |
| PT_202 | W-202 | INACTIVE |

Sources: AGA Report No. 3 (2012), API MPMS Chapter 14.3, OSHA 29 CFR 1910.1000 Table Z-1.

---

## Scoring (100 pts total)

| Subtask | Points | Criterion |
|---------|--------|-----------|
| S1 — Active Tag Presence & Naming | 24 pts (4/tag) | All 6 W-201 tag names created |
| S2 — Data Type = Float | 18 pts (3/tag) | Treat As = Float for each active tag |
| S3 — Min/Max Ranges | 36 pts (3 per limit) | Engineering range within 2% tolerance |
| S4 — Engineering Unit Label | 22 pts (~3/tag) | Label text matches AGA-3 standards doc |

**Pass threshold**: 70 / 100
**Project save**: `C:\Users\Docker\Documents\CrimsonProjects\oilgas_flow.c3`

---

## Verification Strategy

The `export_result.ps1` post-task hook exports all tags to CSV and parses them.
The `verifier.py` function `verify_oilgas_flow_measurement_tags`:
- **GATE 1**: project_found=false → score=0 (do-nothing protection)
- **GATE 2 (wrong-wellsite)**: FT_202 or PT_202 found in export → score=0
- **GATE 3 (wrong-target)**: No W-201 tags found → score=0
- Scores S1–S4 for the 6 active W-201 tags

---

## Anti-Gaming Properties

- **Do-nothing**: No project → score=0
- **Configure all 8 (no judgment)**: FT_202 or PT_202 present → wrong-wellsite → score=0
- **Configure only correct 6**: Full scoring applies
- **Wrong naming**: score=0 via wrong-target gate
