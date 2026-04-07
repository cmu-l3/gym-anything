# trailer_coupler_full_pipeline

## Task Overview

**Occupation**: Trailer Manufacturing Engineer
**Industry**: Heavy Vehicle / Trailer Manufacturing
**Difficulty**: very_hard
**Archetype**: Full pipeline — blank canvas sketch + constrain + extrude + DXF export

A trailer manufacturing engineer must model a U-channel coupler beam cross-section in SolveSpace from scratch. This is the only task among the 5 that requires creating a 3D extrusion (Group.type=5100) in addition to the 2D sketch. The agent must:

1. Open SolveSpace (blank state)
2. Create a new sketch on the XY plane
3. Draw the U-channel profile (8-line closed polygon)
4. Apply all five required dimensional constraints per the spec
5. **Extrude the sketch into a 3D solid** (800 mm depth)
6. Save as `coupler_beam.slvs`
7. Export a DXF to `coupler_beam.dxf`

## Domain Context

5th-wheel king-pin coupler frames in heavy trailers use U-channel longitudinal beams. The cross-section geometry is welded/formed from S355 structural steel. Manufacturing engineers create 3D parametric models before releasing to production — the extrusion converts the 2D profile into the 3D beam shape needed for structural analysis and fab drawings.

## Goal / End State

`coupler_beam.slvs` must exist, be newer than task start, contain five PT_PT_DISTANCE constraints, AND contain an extrude group (Group.type=5100). A DXF must also exist. All three requirements (constraints + extrude + DXF) are hard gates.

## Profile Geometry (from spec)

8-line closed U-channel cross-section:

```
A=(0,0) → B=(180,0) → C=(180,120) → D=(160,120) → E=(160,12) → F=(20,12) → G=(20,120) → H=(0,120) → A
```

The channel walls are 20mm wide (flanges) and 12mm thick (floor).

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| `coupler_beam.slvs` saved and new | 10 | Hard gate: score=0 if missing or not new |
| overall_width = 180 mm | 12 | ±0.5 mm |
| web_height = 120 mm | 12 | ±0.5 mm |
| flange_width = 20 mm | 12 | ±0.5 mm |
| wall_thickness = 12 mm | 12 | ±0.5 mm |
| inner_width = 140 mm | 12 | ±0.5 mm |
| Extrude group (Group.type=5100) present | 20 | Gate: capped to 74 if absent |
| DXF exported and new | 10 | Gate: capped to 74 if missing |
| **Total** | **100** | Pass threshold: 75 |

**Both gates apply**: extrude AND DXF are each independently required. A file with all 5 constraints + DXF but no extrude scores 74 (fails). A file with all 5 constraints + extrude but no DXF also scores 74 (fails).

## Verification Strategy

- `export_result.sh` parses both Group blocks (checking for `Group.type=5100`) and Constraint blocks (type=30)
- `verifier.py` checks all five dimension values, then applies extrude gate, then DXF gate
- The extrude gate and DXF gate are applied AFTER all scoring, preventing score from reaching threshold without both

## Strategy Enumeration (Anti-Pattern 13)

| Strategy | Dims | Extrude | DXF | Score | Pass? |
|----------|------|---------|-----|-------|-------|
| Do nothing | 0 | N | N | 0 | No |
| Dims only, no extrude, no DXF | 60 | N | N | 60→cap74 | No |
| Dims + DXF, no extrude | 60+10=70 | N | Y | 70→cap74 | No |
| Dims + extrude, no DXF | 60+20=80 | Y | N | 80→cap74 | No |
| All correct | 60+20+10=90+10file=100 | Y | Y | 100 | Yes |

## Anti-Pattern Checks

- **AP-4**: No partial credit; all binary. Max partial without extrude/DXF = 70 < 75. ✓
- **AP-10**: Setup has no Python block; spec is on the Desktop. ✓
- **AP-13**: Strategy enumeration table above confirms no gaming shortcut reaches threshold. ✓
