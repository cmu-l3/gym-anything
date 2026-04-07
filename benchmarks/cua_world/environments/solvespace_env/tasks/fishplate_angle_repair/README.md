# fishplate_angle_repair

## Task Overview

**Occupation**: Railway Track Engineer
**Industry**: Railway / Rail Infrastructure
**Difficulty**: very_hard
**Archetype**: Error injection (2 wrong distance + 1 wrong ANGLE constraint → repair per spec)

A SolveSpace drawing of a railway fishplate (splice bar) cross-section has been flagged. Two linear dimension constraints and one angle constraint contain values from a misidentified Rev C template. The corrected Rev D specification is on the Desktop. The agent must:

1. Open `fishplate_start.slvs`
2. Correct the two wrong PT_PT_DISTANCE constraints and the one wrong ANGLE constraint (type=110)
3. Save the corrected file as `fishplate_corrected.slvs`
4. Export a DXF to `fishplate_corrected.dxf`

## Domain Context

Fishplates (splice bars) are steel bars bolted to the web of adjacent rail ends to join them. Cross-section geometry is tightly toleranced to maintain rail head alignment. The angle of the fishplate's web sides determines how the bolt loads transfer through the joint. Using wrong angular specifications causes premature bolt fatigue and track geometry deviation.

## Goal / End State

`fishplate_corrected.slvs` must exist, be newer than task start, and contain the correct width, height, and angle constraints. A DXF export must also exist.

This task is unique among solvespace_env tasks in using a **Constraint.type=110 (ANGLE)** constraint — the agent must identify and modify an angle constraint, not just PT_PT_DISTANCE constraints.

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| `fishplate_corrected.slvs` saved and new | 20 | Hard gate: score=0 if missing or not new |
| width = 160 mm | 20 | ±0.5 mm tolerance |
| height = 22 mm | 20 | ±0.5 mm tolerance |
| angle = 30° | 15 | ±0.5° tolerance; type=110 constraint |
| DXF exported and new | 25 | Gate: capped to 85 if DXF missing |
| **Total** | **100** | Pass threshold: 86 |

## Verification Strategy

- `export_result.sh` parses both `Constraint.type=30` (distance) and `Constraint.type=110` (angle) blocks
- `verifier.py` checks distance values within ±0.5 mm and angle value within ±0.5°
- Timestamp gate: file must be newer than task start
- DXF gate: missing DXF caps score to 74

## Injected Errors (seeded state)

| Constraint | Type | Wrong value | Correct value |
|-----------|------|------------|---------------|
| Total width (A→B) | PT_PT_DISTANCE (30) | 140 mm | 160 mm |
| Total height (A→D) | PT_PT_DISTANCE (30) | 18 mm | 22 mm |
| Web side angle | ANGLE (110) | 25° | 30° |

## Feature Matrix

This task is the only solvespace_env task using ANGLE (type=110) constraints, testing a qualitatively different constraint-editing workflow from the standard PT_PT_DISTANCE tasks.

## Anti-Pattern Checks

- **AP-4**: All binary. Threshold=86. Max without angle=85 < 86. Max without DXF=75 < 86. No shortcut reaches threshold. ✓
- **AP-10**: Setup prints only file size; wrong angle/width/height values not printed. ✓
- **AP-11**: file_existence (20) + absence (0) = 20 < 75. ✓
