# Task: correct_mounting_plate_rev_b

## Overview

**Difficulty:** very_hard
**Occupation:** Design Engineer / CAD Drafter
**Domain:** Instrument / enclosure design / engineering change control

The agent is given a mounting plate CAD file with 6 pre-applied constraints, **3 of which contain obsolete REV-A values** that must be corrected per ECO-2024-0856. The 3 remaining correct constraints must not be modified.

## Profile Geometry

Instrument mounting plate with corner cutout, 6 lines clockwise:

```
F(0,60)────────────────────────E(110,60)
│                                    │
│                               D(110,100)──C(160,100)
│                                           │
A(0,0)─────────────────────────────────B(160,0)
```

Key dimensions (REV-B correct values):
- A→B: 160mm (overall width)
- B→C: 100mm (right side height)
- C→D: 50mm (top-right corner step, 160-110=50)
- D→E: 40mm (cutout depth, 100-60=40)
- E→F: 110mm (inner horizontal)
- F→A: 60mm (left edge height)

## Constraint Errors (REV-A → REV-B)

| REV-A (wrong) | REV-B (correct) | Dimension |
|---------------|-----------------|-----------|
| 120mm ❌ | 160mm ✓ | Overall plate width |
| 75mm ❌ | 100mm ✓ | Overall plate height |
| 35mm ❌ | 50mm ✓ | Top-right corner step |
| 40mm ✓ | (keep) | Corner cutout depth |
| 110mm ✓ | (keep) | Inner horizontal edge |
| 60mm ✓ | (keep) | Left edge height |

## Required Agent Actions

1. Read `/home/ga/Desktop/engineering_change_order.txt` (ECO-2024-0856)
2. Identify and correct the 3 wrong constraint values (120→160, 75→100, 35→50)
3. Leave the 3 correct constraints untouched (40, 110, 60mm)
4. Save the corrected file as `plate_rev_b.slvs`

## Verification

Scored out of 100 points, pass threshold = 80:

| Criterion | Points |
|-----------|--------|
| File saved and new | 20 |
| 160mm correct width present | 13 |
| 100mm correct height present | 13 |
| 50mm correct step present | 13 |
| 40mm cutout preserved | 7 |
| 110mm inner edge preserved | 7 |
| 60mm left height preserved | 7 |
| Wrong 120mm removed | 7 |
| Wrong 75mm removed | 7 |
| Wrong 35mm removed | 6 |

## Files

- `setup_task.sh`: Generates mounting plate with 3 REV-A wrong constraints, places ECO on desktop
- `export_result.sh`: Parses `plate_rev_b.slvs` for constraints, writes JSON
- `verifier.py`: Checks correct values present + wrong values absent + preserved values intact
- `task.json`: Task specification
