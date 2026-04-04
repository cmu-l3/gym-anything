# Task: survey_boundary_overlay

## Overview

**Occupation**: Licensed Land Surveyor / Civil Engineer
**Difficulty**: very_hard
**Environment**: librecad_env@0.1
**Real Data Source**: `floorplan.dxf` — genuine 2-car garage architectural construction drawing (~1.1 MB, 967 entities, 24 layers)

## Task Description

A licensed land surveyor must overlay a complete property boundary survey onto an existing architectural floor plan to prepare a site plan for building permit submission. The agent must know survey drawing conventions (layer naming, bearing/distance notation, easement representation) without any UI navigation instructions.

## Goal

Add a complete property survey overlay to `floorplan.dxf` and save as `floorplan_survey.dxf`. Must include:
1. Property boundary lines on a dedicated boundary layer (e.g., PROPERTY, BOUNDARY, LOT-LINE)
2. Building setback lines on a dedicated setback/zoning layer (e.g., SETBACK, BLDG-LINE, ZONING)
3. At least 2 bearing callouts in standard surveyor notation (e.g., "N45°30'E", "S12°15'W")
4. Utility easement or access easement lines on a dedicated easement layer
5. A north arrow symbol or north arrow text annotation
6. A boundary legend or survey notes block

## What Makes This Hard

- Agent must know survey drawing conventions (metes-and-bounds notation, bearing format)
- No UI instructions — agent must discover LibreCAD's layer and text systems
- Bearing notation has a specific format (N/S + degrees + minutes + E/W) that must be exact
- Must create at least 4 distinct layer types covering boundary, setback, easement, and annotation
- Working on a 967-entity drawing with 24 existing layers increases navigation complexity
- Requires domain knowledge: setback lines are typically dashed; easements are hatched or annotated

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| GATE: Output file created after task start | 0/fail | `file_modified_after_start == True` |
| Property boundary layer present | 20 | New layer with "PROPERTY"/"BOUNDARY"/"LOT"/"SURVEY" etc. |
| Setback/zoning layer present | 15 | New layer with "SETBACK"/"BLDG-LINE"/"ZONING" etc. |
| Boundary line entities (≥ 4) | 20 | Line/polyline entities on boundary layer |
| Bearing notation text (≥ 2) | 20 | Text matching N/S + degrees + E/W pattern |
| Easement/setback entities (≥ 2) | 15 | Entities on easement or setback layer |
| Legend text or north arrow | 10 | Text with "LEGEND"/"NOTES"/"NORTH" or NORTH layer |

**Pass threshold**: 65/100

## Key Edge Cases

- Agent might use "C-PROP" (AIA civil layer) instead of "PROPERTY" — handled by CADASTRAL/PARCEL keywords
- Agent might write bearings as "N45.5E" without degree symbol — handled by flexible regex
- Agent might combine setback and easement on one layer — partial credit still awarded
- Agent might add excellent boundary work but miss legend — can still pass with 65+ pts
