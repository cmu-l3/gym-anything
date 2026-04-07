# sensor_housing_from_spec

## Task Overview

**Occupation**: Instrumentation Engineer
**Industry**: Process Instrumentation / Industrial Automation
**Difficulty**: very_hard
**Archetype**: Specification-driven creation from blank canvas

An instrumentation engineer must create a 2D cross-section sketch of a differential pressure transmitter housing from scratch in SolveSpace. A detailed specification document on the Desktop provides the geometry and all required dimensional constraints. The agent must:

1. Open SolveSpace (blank state)
2. Create a new sketch on the XY plane
3. Draw the stepped-rectangle housing profile (8-line closed polygon)
4. Apply all five required dimension constraints per the spec
5. Save as `sensor_housing.slvs`
6. Export a DXF to `sensor_housing.dxf`

## Domain Context

Differential pressure transmitters used in process plants have machined housings with precise exterior geometry. Instrumentation engineers create CAD drawings before releasing to machining. This task requires the engineer to translate a written specification document into a constrained SolveSpace sketch — a real-world workflow that requires reading the spec, planning the geometry, and applying the right dimensional constraints.

## Goal / End State

`sensor_housing.slvs` must exist, be newer than task start, and contain the five specified PT_PT_DISTANCE constraints. A DXF must also exist.

For `very_hard`: Description names the task goal but does NOT provide the geometry or dimensions — the agent must find and read the spec file on the Desktop.

## Profile Geometry (from spec)

The housing is a stepped rectangle with 8 vertices:

```
A=(0,0) → B=(96,0) → C=(96,48) → D=(72,48) → E=(72,80) → F=(24,80) → G=(24,48) → H=(0,48) → A
```

The step at D-E-F-G is the mounting boss protruding above the main body.

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| `sensor_housing.slvs` saved and new | 10 | Hard gate: score=0 if missing or not new |
| body_width = 96 mm | 15 | ±0.5 mm (A→B horizontal) |
| body_height = 48 mm AND boss_width = 48 mm | 30 | Both must be present (count ≥ 2 for value 48mm); 15 pts if only one present |
| boss_height = 32 mm | 15 | ±0.5 mm (D→E vertical) |
| left_boss_offset = 24 mm | 10 | ±0.5 mm (A→G horizontal) |
| DXF exported and new | 20 | Gate: capped to 74 if DXF missing |
| **Total** | **100** | Pass threshold: 75 |

**Note on 48mm**: body_height (48mm) and boss_width (48mm) share the same numeric value. The verifier requires count ≥ 2 for the value 48mm to award full points; a single 48mm constraint scores 15 pts (partial).

## Verification Strategy

- `export_result.sh` parses type=30 constraints from `sensor_housing.slvs`
- `verifier.py` checks for each required value; counts occurrences of 48mm
- DXF gate (capped if missing)

## Anti-Pattern Checks

- **AP-2** (feature matrix): This task is the only "blank canvas creation from spec" task among the 5, using the specification-driven discovery archetype. ✓
- **AP-4** (partial sum < threshold): Max partial = 10 (file) + 15 (partial 48mm) = 25 < 75. ✓
- **AP-10**: Setup has no Python block that could leak geometry; spec values are on the Desktop for the agent to read directly. ✓
