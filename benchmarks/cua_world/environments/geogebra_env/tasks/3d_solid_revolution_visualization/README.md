# Task: 3D Solid of Revolution Visualization

## Overview

**Difficulty**: Very Hard
**Occupation**: Mathematical Science Teachers, Postsecondary (Calculus II)
**Timeout**: 720 seconds, 80 max steps

A calculus professor creating interactive 3D course materials for a Calculus II unit on solids of revolution. This is a genuine professional workflow — creating 3D GeoGebra applets for the disk/washer method of computing volumes is a recognized best practice in undergraduate calculus instruction.

## What Makes This Very Hard

The agent must:
1. **Switch to GeoGebra 3D Graphics view** — not the default 2D view
2. **Know the parametric Surface command syntax** for a surface of revolution:
   `Surface(sqrt(u)*cos(v), u, sqrt(u)*sin(v), u, 0, 4, v, 0, 2*pi)` — complex 3D command with 9 parameters
3. **Create a dynamic cross-section** — a circle of radius sqrt(a) at position x=a, linked to a slider
4. **Implement the disk method formula** — display V = π·a²/2 computed in GeoGebra
5. **Coordinate all these elements interactively** — slider controls both the cross-section plane AND the volume display simultaneously

There is no single obvious path to accomplishing this — the agent must know GeoGebra 3D commands (Surface, Cone, etc.), understand the mathematical connection between the function and the solid, and chain multiple interactive elements.

## Goal (End State)

A file `solid_revolution.ggb` in `~/Documents/GeoGebra/projects/` in **3D Graphics view** containing:
- The curve f(x) = sqrt(x) for x ∈ [0, 4]
- The surface of revolution (paraboloid formed by rotating √x around x-axis)
- A slider `a` ∈ [0, 4]
- A circular cross-section at x = a with radius = sqrt(a)
- Text display: "V = π·a²/2" or similar volume formula

## Mathematical Background

**Function**: f(x) = √x rotated around the x-axis
- **Parametric surface**: x = u, y = √u·cos(v), z = √u·sin(v), for u ∈ [0,4], v ∈ [0, 2π]
- **Cross-section at x = a**: circle of radius r = √a, area = πr² = πa
- **Volume by disk method**: V = π·∫₀ᵃ x dx = π·[x²/2]₀ᵃ = π·a²/2
- **Total volume [0,4]**: V = π·16/2 = 8π ≈ 25.133

## Verification Criteria (100 points total)

| Criterion | Points | How Checked |
|-----------|--------|-------------|
| File created during task | 20 | mtime ≥ task start |
| 3D Graphics view used | 20 | `geogebra3d.xml` present or 3D element types |
| sqrt(x) function in construction | 20 | `sqrt(` or `x^0.5` pattern in XML |
| Surface command (solid of revolution) | 20 | `<command name="Surface">` in XML |
| Slider + volume text annotation | 20 | slider element + text element (partial credit for either) |

**Pass threshold**: 70 points

**Gate**: No 3D view + no Surface command → score capped at 69 (prevents 2D-only solutions)

## Key GeoGebra 3D Commands

```
# Switch to 3D view: View > 3D Graphics (or Alt+3)

# Define the paraboloid surface
Surface(sqrt(u) * cos(v), u, sqrt(u) * sin(v), u, 0, 4, v, 0, 2 * pi)

# Slider for cross-section position
a = Slider(0, 4, 0.1)

# Cross-sectional circle at x = a
Circle((a, 0, 0), sqrt(a), (1, 0, 0))

# Volume formula display
Text("V = π·" + a + "² / 2 = " + (π * a^2 / 2), (2, 2, 0))

# The exact total volume: 8π ≈ 25.133
```
