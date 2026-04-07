# Task: fix_channel_section_errors

## Overview

**Difficulty:** very_hard
**Occupation:** CAD Checker / Quality Engineer
**Domain:** Structural steelwork fabrication / drawing office

The agent is given a SolveSpace C-channel cross-section with 5 pre-applied dimensional constraints, **3 of which are wrong**. It must read the approved drawing revision on the desktop, identify which values are incorrect, remove the wrong constraints, and add the correct ones.

## Profile Geometry

C-channel cross-section (clockwise from A, web on left side):

```
H(0,83)──────────────────────────G(100,83)
│                                      │
│        (hollow interior)             │
│                                F(100,65)──E(20,65)
│                                │
│                                D(20,18)──C(100,18)
│                                      │
A(0,0)───────────────────────────B(100,0)
```

## Constraint Errors

| Value in file | Correct value | Measurement |
|---------------|---------------|-------------|
| 65mm ❌ | 83mm ✓ | Outer wall height (H→A) |
| 25mm ❌ | 18mm ✓ | Flange thickness (B→C) |
| 32mm ❌ | 47mm ✓ | Web inner height (D→E) |
| 100mm ✓ | (keep) | Bottom width |
| 80mm ✓ | (keep) | Inner flange width |

## Required Agent Actions

1. Read `/home/ga/Desktop/channel_approved_drawing.txt` (REV-D)
2. Examine each dimensional constraint value in the SolveSpace file
3. Delete/edit all three wrong constraints (65→83, 25→18, 32→47)
4. Ensure the two correct constraints remain unchanged
5. Save corrected file as `channel_corrected.slvs`

## Verification

Scored out of 100 points, pass threshold = 80:

| Criterion | Points |
|-----------|--------|
| File saved and new | 20 |
| 83mm outer wall present | 10 |
| 18mm flange thickness present | 10 |
| 47mm web inner height present | 10 |
| 100mm width preserved | 10 |
| 80mm inner width preserved | 10 |
| Wrong 65mm removed | 10 |
| Wrong 25mm removed | 10 |
| Wrong 32mm removed | 10 |

## Files

- `setup_task.sh`: Generates C-channel with 3 wrong constraints, places revision notice on desktop
- `export_result.sh`: Parses `channel_corrected.slvs` for constraints, writes JSON
- `verifier.py`: Checks correct values present + wrong values absent
- `task.json`: Task specification
