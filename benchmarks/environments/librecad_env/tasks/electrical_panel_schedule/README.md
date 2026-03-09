# Task: electrical_panel_schedule

## Overview

**Occupation**: Electrical Engineering Technician
**Difficulty**: very_hard
**Environment**: librecad_env@0.1
**Real Data Source**: `floorplan.dxf` — genuine 2-car garage architectural construction drawing (~1.1 MB, 967 entities, 24 layers)

## Task Description

An electrical engineering technician must create a complete residential electrical panel schedule overlay on an architectural floor plan to prepare the electrical drawings for building permit submission. The agent must know electrical drawing conventions (NEC panel schedule format, circuit numbering, load calculations) without any UI navigation instructions.

## Goal

Add a complete electrical panel schedule to `floorplan.dxf` and save as `floorplan_electrical.dxf`. Must include:
1. Panel schedule table with circuit numbers and descriptions on an E-PANEL or equivalent layer
2. Branch circuit annotations (circuit numbers on plan) on a circuit layer
3. Load calculation text (watts, VA, or amps values)
4. Main breaker/panel rating annotation (e.g., "200A MAIN", "100 AMP PANEL")
5. At least 4 circuit descriptions (e.g., LIGHTING, RECEPTACLES, HVAC, DRYER, GARAGE)
6. Electrical notes or specifications layer with installation requirements

## What Makes This Hard

- Agent must know residential NEC panel schedule format without prompting
- No UI instructions — agent must discover LibreCAD's text, line, and layer tools
- Circuit descriptions require electrical domain knowledge (standard branch circuit loads)
- Load calculations require numeric electrical values (W, VA, A) in specific format
- Working on a 967-entity drawing with 24 existing layers adds navigation complexity
- Panel schedule is a structured table requiring both line entities and precise text placement
- Must meet 6 independent criteria covering different aspects of electrical drawings

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| GATE: Output file created after task start | 0/fail | `file_modified_after_start == True` |
| Panel schedule layer present | 20 | New layer with "E-PANEL"/"PANEL"/"SCHEDULE"/"PANELBOARD" etc. |
| Branch circuit layer or annotations | 15 | New layer with "CIRCUIT"/"CKT"/"BRANCH"/"ELEC" OR circuit numbers ≥ 3 |
| Circuit descriptions (≥ 4) | 20 | Text with LIGHTING/RECEPTACLE/HVAC/DRYER/KITCHEN/etc. |
| Load calculation values (≥ 3) | 20 | Text with W/VA/A/AMP/KW numerical values |
| Main breaker/panel rating | 15 | Text with "200A"/"100 AMP"/"MAIN" etc. |
| Electrical notes/specifications | 10 | Text with NOTE/SPEC/REQUIRE or dedicated notes layer |

**Pass threshold**: 60/100

## Key Edge Cases

- Agent might use "ELECTRICAL" as a single catch-all layer — partial credit for circuit annotations
- Agent might write "200 AMPS" instead of "200A" — handled by flexible regex
- Agent might list loads as "1800W" per circuit or total connected load — both count
- Agent might not add a dedicated notes layer but include NEC references in panel table — counts
- Agent might label circuits as "CKT-1" or "#1" or "BR-1" — all accepted by circuit number regex
