# pipe_support_flange_repair

## Task Overview

**Occupation**: Piping Engineer
**Industry**: Oil & Gas / Process Piping
**Difficulty**: very_hard
**Archetype**: Error injection (5 wrong distance constraints → repair per revised spec)

A QA review has flagged a SolveSpace drawing of a pipe support T-flange cross-section. All five dimensional constraints in the file were entered from a superseded revision (Rev B) and are incorrect. A corrected specification sheet (Rev C) is on the Desktop. The agent must:

1. Open the existing file `flange_start.slvs`
2. Locate and correct all five PT_PT_DISTANCE (type=30) constraints
3. Save the corrected file as `flange_corrected.slvs`
4. Export a DXF of the sketch to `flange_corrected.dxf`

## Domain Context

Pipe support flanges are structural components used to anchor and support process pipes in oil & gas facilities. Drawings are revision-controlled; when a superseded revision's values are used, the fabricated part will not fit. The engineer must reconcile the SolveSpace model against the latest approved specification before releasing for fabrication.

## Goal / End State

The file `flange_corrected.slvs` must exist, be newer than the task start timestamp, and contain five PT_PT_DISTANCE constraints whose values match the Rev C specification (see metadata). A DXF export of the sketch must also exist.

For `very_hard`: The description does NOT tell the agent which constraints are wrong or what the correct values are — the agent must find the spec file on the Desktop and derive the required changes.

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| `flange_corrected.slvs` saved and new | 15 | Hard gate: score=0 if missing or not new |
| base_width = 120 mm | 12 | ±0.5 mm tolerance |
| base_height = 12 mm | 12 | ±0.5 mm tolerance |
| hub_width = 36 mm | 12 | ±0.5 mm tolerance |
| hub_height = 60 mm | 12 | ±0.5 mm tolerance |
| left_offset = 42 mm | 12 | ±0.5 mm tolerance |
| DXF exported and new | 25 | Gate: capped to 74 if DXF missing |
| **Total** | **100** | Pass threshold: 75 |

## Verification Strategy

- `export_result.sh` parses `flange_corrected.slvs` for all `Constraint.type=30` blocks, extracts `Constraint.valA` floats, and writes them to the result JSON
- `verifier.py` checks each expected value is present within ±0.5 mm
- Timestamp gate: file must be newer than task start
- DXF gate: missing DXF caps score to 74

## Injected Errors (seeded state)

| Dimension | Wrong value (Rev B) | Correct value (Rev C) |
|-----------|--------------------|-----------------------|
| Base width (A→B) | 90 mm | 120 mm |
| Base height (A→H) | 8 mm | 12 mm |
| Hub width (G→D) | 24 mm | 36 mm |
| Hub height (D→E) | 40 mm | 60 mm |
| Left offset (A→G) | 33 mm | 42 mm |

## Anti-Pattern Checks

- **AP-4** (partial sum < threshold): All criteria are binary, no partial credit. Max score without DXF gate = 75; DXF gate caps to 74 if not exported. ✓
- **AP-10** (print leak): Setup script prints only file path and size, never the wrong or correct constraint values. ✓
- **AP-11** (empty file pass): file_existence (15) + absence criteria (0, no absence checks) = 15 < 75. ✓
