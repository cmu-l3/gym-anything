# Task: Parabola Focus-Directrix Construction

## Overview

**Difficulty**: Hard
**Occupation**: Secondary School Teacher (Pre-Calculus / Algebra II)
**Timeout**: 480 seconds, 60 max steps

A pre-calculus teacher creating an interactive GeoGebra applet that demonstrates the geometric (locus) definition of the parabola — the set of all points equidistant from a focus and a directrix. This is a core concept in the Common Core Pre-Calculus curriculum (CCSS-Math HSG-GPE.A.2) and is more pedagogically powerful than just typing `y = x^2/4p` because students can see the geometric construction in action.

## What Makes This Hard

The agent must:
1. Know that GeoGebra has a **Locus** tool/command (not obvious — it's under the Geometric Tools dropdown or via the input bar as `Locus(tracePoint, driverPoint)`)
2. Construct the geometric scaffolding needed before applying the Locus: a point on the directrix, the perpendicular from that point, the midpoint of the segment from the directrix point to the focus, and the circle/perpendicular bisector to find equidistant points
3. Use the correct tool/command syntax
4. Add meaningful annotations (not just create the locus and stop)
5. Save in the right location

## Goal (End State)

A file `parabola_locus.ggb` saved in `~/Documents/GeoGebra/projects/` that contains:
- Focus point F at (0, 1)
- Directrix line at y = -1
- A moveable/driver point on the directrix
- A GeoGebra Locus object tracing the parabola
- At least one text or distance annotation

## Verification Criteria (100 points total)

| Criterion | Points | How Checked |
|-----------|--------|-------------|
| File created during task | 20 | File exists AND modification time ≥ task start |
| Focus point near (0, 1) | 20 | Point element with coords (0±0.15, 1±0.15) |
| Directrix line at y = -1 | 20 | Line element with horizontal equation y = -1 (±0.15) |
| Locus command present | 20 | `<command name="Locus">` in geogebra.xml |
| Text/distance annotation | 20 | `<element type="text">` or distance/length element present |

**Pass threshold**: 70 points (≥3 criteria fully met, or partial on some)

## Real Data / Mathematical Context

This construction is based on the analytical definition of the parabola:
- Focus F = (0, 1) → this gives p = 1 in the standard form y = x²/(4p) = x²/4
- Directrix y = -1
- The resulting parabola passes through (2, 1), (-2, 1), (1, 1/4), etc.
- The equal-distance property: for any point (x, y) on the parabola, distance to F = distance to directrix

**Standard Form**: y = x²/4 (for reference, but agent must construct geometrically, not by formula)

## Approach Notes (for Task Creator Reference Only)

The GeoGebra Locus command syntax:
```
Locus(tracedPoint, driverPoint)
```
Where:
- `driverPoint` moves along a predefined path (e.g., the directrix line)
- `tracedPoint` depends on `driverPoint` (e.g., the perpendicular bisector midpoint)

A typical construction sequence:
1. Create point A = (0, 1) as focus
2. Create line: `y = -1` for directrix
3. Create point B on the directrix line (moveable)
4. Create midpoint M of segment FB (or perpendicular bisector of FB)
5. Use `Locus(M, B)` to trace the parabola

But the agent must discover this — the task description does NOT spell out these steps.

## Files

- `task.json` — Task specification
- `setup_task.sh` — Launches GeoGebra, records baseline
- `export_result.sh` — Extracts construction data from saved .ggb file
- `verifier.py` — Programmatic verification
