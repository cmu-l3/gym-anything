# Task: dimension_i_beam_profile

## Overview

**Difficulty:** very_hard
**Occupation:** Structural Design Engineer
**Domain:** Structural steel fabrication / building engineering

The agent is given a SolveSpace sketch of a custom asymmetric I-beam cross-section with all geometry present (12 line segments, closed loop) but **no dimensional constraints**. It must read the structural specification on the desktop and apply 8 specific PT_PT_DISTANCE constraints before saving as a new file.

## Profile Geometry

The I-beam cross-section (clockwise from bottom-left corner A):

```
G(120,90)────────────────────H(0,90)
     │                           │
F(120,72)──E(80,72)   I(0,72)──J(30,72)
           │              │
C(120,12)──D(80,12)   K(30,12)──L(0,12)
     │                           │
B(120,0) ────────────────────── A(0,0)
```

- 12 lines forming a closed asymmetric I-beam profile
- Right overhang (C→D, E→F): 40mm
- Left overhang (I→J, K→L): 30mm
- Bottom flange thickness: 12mm
- Top flange thickness: 18mm
- Web clear height: 60mm (D to E, or J to K)
- Web thickness: 50mm (horizontal, J to E)
- Overall width: 120mm
- Overall height: 90mm

## Required Agent Actions

1. Open and read `/home/ga/Desktop/i_beam_specification.txt`
2. Identify all 8 required dimensional values
3. Apply 8 PT_PT_DISTANCE constraints (one per dimension) to the sketch
4. Save the fully constrained file as `i_beam_constrained.slvs`

## Verification

Scored out of 100 points, pass threshold = 80:

| Criterion | Points |
|-----------|--------|
| File saved and new | 20 |
| ≥8 PT_PT_DISTANCE constraints | 10 |
| 120mm overall width | 10 |
| 90mm overall height | 10 |
| 12mm bottom flange | 10 |
| 18mm top flange | 10 |
| 40mm right overhang | 10 |
| 30mm left overhang | 10 |
| 60mm web clear height | 5 |
| 50mm web thickness | 5 |

## Files

- `setup_task.sh`: Generates `i_beam_profile.slvs` (12-line I-beam, geometry only), places spec on desktop, launches SolveSpace
- `export_result.sh`: Parses `i_beam_constrained.slvs` for PT_PT_DISTANCE constraints, writes JSON
- `verifier.py`: Checks file freshness + 8 specific constraint values
- `task.json`: Task specification
