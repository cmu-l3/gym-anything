# Task: hvac_system_overlay

## Overview

**Occupation**: Mechanical Engineer / HVAC Technician
**Difficulty**: very_hard
**Environment**: librecad_env@0.1
**Real Data Source**: `floorplan.dxf` — genuine 2-car garage architectural construction drawing (~1.1 MB, 967 entities, 24 layers)

## Task Description

A mechanical engineer must overlay a complete HVAC ductwork system on a real architectural floor plan for a mechanical building permit. The agent must know HVAC drawing conventions (layer naming, duct symbols, sizing callout formats) without any UI navigation instructions.

## Goal

Add a complete HVAC system overlay to `floorplan.dxf` and save as `floorplan_hvac.dxf`. Must include:
1. Supply air duct routing on dedicated HVAC supply layer(s)
2. Return air duct routing on dedicated HVAC return layer(s)
3. At least 3 diffuser/register locations (circle symbols)
4. Duct sizing callouts (e.g., "12x8", "300 CFM")
5. Air handler unit label
6. System notes or equipment schedule layer

## What Makes This Hard

- Agent must know HVAC drawing conventions (ASHRAE, AIA mechanical layers)
- No UI instructions — agent must discover how to create layers with specific properties
- Agent must make engineering judgment calls about duct routing on a real building
- Requires 6 independent criteria covering different aspects of an HVAC drawing
- Working on a 967-entity drawing with 24 existing layers increases navigation complexity
- Duct sizing notation requires domain knowledge ("12x8", "CFM", etc.)

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| GATE: Output file created after task start | 0/fail | `file_modified_after_start == True` |
| Supply air layer present | 20 | New layer with "SUPPLY"/"SA"/"HVAC-S" etc. |
| Return air layer present | 15 | New layer with "RETURN"/"RA"/"HVAC-R" etc. |
| Supply duct line entities (≥ 5) | 20 | Lines on supply layer |
| Diffuser symbols — circles (≥ 3) | 20 | Circle entities on any HVAC layer |
| Duct sizing text callouts (≥ 3) | 15 | Text matching "NNxNN", "NNN CFM" etc. |
| Equipment label or system notes | 10 | Text with "AHU"/"AIR HANDLER"/"UNIT" or notes layer |

**Pass threshold**: 65/100

## Key Edge Cases

- Agent might use "M-SA" or "M-RA" (AIA mechanical layers) — handled by keyword matching
- Agent might route ducts but on a generic "HVAC" layer — partial credit for line entities
- Agent might use "x" notation (12x8) or "CFM" notation — both accepted
- Agent might create excellent duct routing but forget the return layer — still can pass
