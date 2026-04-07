# Task: constrain_stiffener_rib_dims

## Overview

**Difficulty:** very_hard
**Occupation:** Structural Steel Detailer / Fabrication Engineer
**Domain:** Structural steelwork fabrication / plasma cutting

The agent is given an unconstrained web stiffener rib profile in SolveSpace. It must read the fabrication drawing on the desktop and apply 6 specific dimensional constraints to the stepped plate cross-section.

## Profile Geometry

Web stiffener rib (stepped gusset plate for haunch connection), 6 lines clockwise:

```
F(0,70)──────────────────────────E(100,70)
│                                     │
│                                D(100,25)──C(130,25)
│                                           │
A(0,0)─────────────────────────────────B(130,0)
```

Key dimensions:
- A→B: 130mm (overall base)
- B→C: 25mm (bottom ledge / step height)
- C→D: 30mm (step depth, 130-100=30)
- D→E: 45mm (web height, 70-25=45)
- E→F: 100mm (top edge)
- F→A: 70mm (total height)

## Required Agent Actions

1. Read `/home/ga/Desktop/stiffener_fabrication_drawing.txt`
2. Map each listed dimension to the correct line segment in the sketch
3. Apply 6 PT_PT_DISTANCE constraints
4. Save the constrained file as `stiffener_constrained.slvs`

## Verification

Scored out of 100 points, pass threshold = 80:

| Criterion | Points |
|-----------|--------|
| File saved and new | 20 |
| ≥6 PT_PT_DISTANCE constraints | 10 |
| 130mm overall base | 12 |
| 25mm ledge height | 12 |
| 30mm ledge depth | 12 |
| 45mm web height | 12 |
| 100mm top edge | 11 |
| 70mm total height | 11 |

## Files

- `setup_task.sh`: Generates stiffener rib profile (geometry only), places fabrication drawing on desktop
- `export_result.sh`: Parses `stiffener_constrained.slvs` for constraints, writes JSON
- `verifier.py`: Checks file freshness + 6 specific constraint values
- `task.json`: Task specification
