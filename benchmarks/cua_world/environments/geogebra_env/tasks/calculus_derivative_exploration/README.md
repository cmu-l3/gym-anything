# Task: Calculus Derivative Interactive Explorer

## Overview

**Difficulty**: Very Hard
**Occupation**: Mathematical Science Teachers, Postsecondary (Calculus I course)
**Timeout**: 600 seconds, 75 max steps

A calculus professor creating interactive course materials for a Calculus I unit on derivatives and critical points. This is a real professional workflow: GeoGebra is used extensively at universities to create interactive applets that students can manipulate to develop geometric intuition about calculus concepts.

## What Makes This Very Hard

The agent must discover and combine FOUR non-obvious GeoGebra features:

1. **Derivative(f)** — GeoGebra's symbolic differentiation command (must know to type this in input bar or use CAS)
2. **Tangent(point, function)** — creates a tangent line at a specific point on a function. Not found in the basic toolbar; requires knowing the command.
3. **Dynamic tangent (slider/draggable point)** — creating a point constrained to the function curve (via `PointIn(f)` or via a slider `t` and then creating point `(t, f(t))`), then linking the tangent to that point so it moves as the point moves.
4. **Extremum(f, a, b)** or **Root(f', a, b)** — computing critical points programmatically rather than by manual inspection.

The agent must figure out HOW to achieve all four without being told which menus or commands to use.

## Goal (End State)

A file `derivative_explorer.ggb` in `~/Documents/GeoGebra/projects/` containing:
- The cubic function f(x) = x³ - 3x + 1
- The derivative function f'(x) = 3x² - 3 (computed via GeoGebra's Derivative command)
- A moveable tangent line (tangent to f at a draggable or slider-controlled point)
- Critical points at x = -1 (local max, f(-1) = 3) and x = 1 (local min, f(1) = -1)
- Numerical display of the instantaneous slope at the current point

## Mathematical Background

**Function**: f(x) = x³ - 3x + 1
- **Derivative**: f'(x) = 3x² - 3
- **Critical points**: f'(x) = 0 → 3x² - 3 = 0 → x = ±1
  - f(-1) = (-1)³ - 3(-1) + 1 = -1 + 3 + 1 = **3** (local maximum)
  - f(1) = (1)³ - 3(1) + 1 = 1 - 3 + 1 = **-1** (local minimum)
- **Second derivative**: f''(x) = 6x → inflection point at x = 0, f(0) = 1

## Verification Criteria (100 points total)

| Criterion | Points | How Checked |
|-----------|--------|-------------|
| File created during task | 20 | mtime ≥ task start |
| Cubic function f(x) = x³-3x+1 present | 20 | `x^3` pattern in function element (partial credit if any function) |
| Derivative command/function found | 20 | `<command name="Derivative">` or f' expression |
| Tangent line with moveable point | 20 | `<command name="Tangent">` (partial if slider present) |
| Critical points identified | 20 | `<command name="Extremum/Root">` or points near x=±1 |

**Pass threshold**: 70 points

## GeoGebra Commands the Agent Must Discover

```
f(x) = x^3 - 3x + 1         # define the function
g(x) = Derivative(f)         # compute derivative symbolically → g(x) = 3x² - 3
A = PointIn(f)               # create draggable point on f (or use slider t + point (t, f(t)))
t = Tangent(A, f)            # tangent line at point A
s = Extremum(f, -2, 0)       # local max at x=-1
s2 = Extremum(f, 0, 2)       # local min at x=1
slope = Slope(t)             # display slope value
```
