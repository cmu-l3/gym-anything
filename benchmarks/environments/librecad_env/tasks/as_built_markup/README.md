# Task: as_built_markup

## Overview

**Occupation**: Architectural Drafter / Construction Manager
**Difficulty**: very_hard
**Environment**: librecad_env@0.1
**Real Data Source**: `floorplan.dxf` — genuine 2-car garage architectural construction drawing (~1.1 MB, 967 entities, 24 layers)

## Task Description

An architectural drafter must prepare a real architectural floor plan as an official as-built record drawing. Field inspections revealed the constructed building differs from the design in several ways. The agent must mark up the drawing with as-built documentation per standard architectural practice — without any UI instructions.

## Goal

Transform `floorplan.dxf` into a professional as-built record drawing (`floorplan_asbuilt.dxf`) that:
1. Has appropriate layer organization distinguishing original design from field-verified conditions
2. Contains an as-built status stamp (e.g., "AS-BUILT", "RECORD DRAWING")
3. Documents at least 2 specific field changes with descriptive notes
4. Adds new entities representing field condition markups

## What Makes This Hard

- Agent must know what as-built documentation looks like in architectural practice
- No UI navigation steps provided — agent must discover how to create layers, add text, etc.
- Must make professional judgment calls about layer naming (AIA standards), annotation content, and placement
- Starting from a real 967-entity drawing with 24 existing layers adds navigation complexity
- Multiple independent subtasks must all be completed (layers + stamp + notes + entities)

## Verification Strategy

The verifier parses the output DXF using ezdxf and checks:

| Criterion | Points | Check |
|-----------|--------|-------|
| GATE: Output file created after task start | 0/fail | `file_modified_after_start == True` |
| As-built themed layer present | 20 | New layer with name containing "AS-BUILT", "RECORD", "FIELD-VERIFIED" etc. |
| Change/notes/markup layer present | 15 | New layer with "CHANGE", "NOTES", "REVISION", "MARKUP" etc. |
| As-built stamp text present | 20 | Text entity containing "AS-BUILT", "RECORD DRAWING", etc. |
| Field change text (≥ 2 entries on new layers) | 20 | Text entities with field change keywords on as-built layers |
| Minimum 5 new entities vs baseline | 15 | `output_entities - 967 >= 5` |
| File size > 50 KB | 10 | Ensures non-trivial modifications |

**Pass threshold**: 60/100

## Files

- `task.json` — Task specification with metadata
- `setup_task.sh` — Kills LibreCAD, clears output, records baseline, opens floorplan.dxf
- `export_result.sh` — Kills LibreCAD, parses output DXF with ezdxf, writes result JSON
- `verifier.py` — Reads result JSON, applies multi-criterion scoring
- `README.md` — This file

## Key Edge Cases

- Agent may use "A-ABLT" (AIA standard) instead of "AS-BUILT" — handled by flexible keyword matching
- Agent may forget to save to the correct path — caught by output file check
- Agent may copy floorplan.dxf without modifications — caught by entity count delta check
- Agent may save to the original floorplan.dxf path — this is a wrong-path failure (no output found)
