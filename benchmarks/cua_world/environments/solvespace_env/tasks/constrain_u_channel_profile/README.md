# Task: constrain_u_channel_profile

## Overview

**Difficulty:** very_hard
**Occupation:** Tooling Engineer / Die Designer
**Domain:** Press tooling / die manufacturing

The agent is given an unconstrained U-channel die insert cross-section profile in SolveSpace. It must read the tooling design specification on the desktop and apply 5 specific dimensional constraints before saving as a new file.

## Profile Geometry

U-channel (press-formed die insert), 8 lines clockwise from bottom-left:

```
H(0,70)──────────────────────────────────────────────C(120,70)
│  G(15,70)──────────────────────────────D(105,70)   │
│  │                                          │       │
│  │          (channel cavity)               │       │
│  │                                          │       │
│  F(15,15)──────────────────────────E(105,15)       │
│                                                     │
A(0,0)───────────────────────────────────────────B(120,0)
```

Key dimensions:
- Overall width A→B: 120mm
- Leg height B→C: 70mm
- Wall thickness C→D (also G→H): 15mm each
- Inner depth D→E: 55mm (70 - 15 = 55)
- Inner width E→F: 90mm (105 - 15 = 90)

## Required Agent Actions

1. Read `/home/ga/Desktop/tooling_design_spec.txt`
2. Understand what each listed dimension corresponds to in the sketch
3. Apply 5 PT_PT_DISTANCE constraints to fully define the profile
4. Save the constrained file as `u_channel_constrained.slvs`

## Verification

Scored out of 100 points, pass threshold = 80:

| Criterion | Points |
|-----------|--------|
| File saved and new | 20 |
| ≥5 PT_PT_DISTANCE constraints | 10 |
| 120mm overall width | 14 |
| 70mm leg height | 14 |
| 15mm wall thickness | 14 |
| 55mm inner clear depth | 14 |
| 90mm inner clear width | 14 |

## Files

- `setup_task.sh`: Generates U-channel profile (geometry only), places spec on desktop, launches SolveSpace
- `export_result.sh`: Parses `u_channel_constrained.slvs` for constraints, writes JSON
- `verifier.py`: Checks file freshness + 5 specific constraint values
- `task.json`: Task specification
