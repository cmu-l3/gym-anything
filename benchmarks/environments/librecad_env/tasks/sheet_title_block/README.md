# Task: sheet_title_block

## Overview

**Occupation**: Project Architect / Architectural Drafter
**Difficulty**: very_hard
**Environment**: librecad_env@0.1
**Real Data Source**: `floorplan.dxf` — genuine 2-car garage architectural construction drawing (~1.1 MB, 967 entities, 24 layers)

## Task Description

A project architect must prepare a real architectural floor plan for formal permit submission by adding a complete professional title block. The agent must know standard title block requirements without being told which menus to use, which layers to create, or what text to add.

## Goal

Add a complete title block to `floorplan.dxf` and save as `floorplan_sheet.dxf`. The title block must include:
1. Title block border/frame (line entities forming a structured grid)
2. Project identification information (title, address, owner)
3. Drawing number and sheet designation
4. Drawing scale annotation
5. Designated space for architect's seal with appropriate text
6. Revision history section

## What Makes This Hard

- Agent must know what a professional title block contains (no instructions given)
- Must create correct layer structure for different title block zones
- Must know standard drawing conventions (AIA layers, sheet naming, scale notation)
- Working from a 967-entity real drawing adds navigation complexity
- All 7 criteria are independent subtasks that must each be completed
- No UI navigation hints given for LibreCAD menus

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| GATE: Output file created after task start | 0/fail | `file_modified_after_start == True` |
| Title block border layer + ≥8 line entities | 20 | New layer with "BORDER"/"TB"/"FRAME" + line count |
| Title information/project layer | 15 | New layer with "INFO"/"TITLE"/"PROJECT" |
| Project info text content | 15 | Text with "PROJECT"/"ADDRESS"/"BUILDING" etc. |
| Drawing number/sheet designation | 15 | Text with "SHEET"/"DWG"/"A-"/"PAGE" etc. |
| Scale annotation | 10 | Text with "SCALE"/"1:"/"1/4" etc. |
| Seal/approval/permit text | 15 | Text with "SEAL"/"PERMIT"/"REVIEW" etc. |
| Revision history text | 10 | Text with "REV"/"REVISION"/"DATE" etc. |

**Pass threshold**: 60/100

## Key Edge Cases

- Agent might use AIA layer names (TB-BORDER, TB-INFO, TB-SEAL) — all handled
- Agent might place all title block elements on one layer — still partially scored
- Agent might not add scale annotation — 10 pts lost but can still pass
- Empty revision section — 10 pts lost but can still pass with other criteria
