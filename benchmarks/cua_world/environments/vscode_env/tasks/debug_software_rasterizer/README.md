# Debug Software Rasterizer (`debug_software_rasterizer@1`)

## Overview
This task evaluates the agent's ability to debug a Python-based 3D software rasterizer. The agent must identify and fix 5 mathematical and logical bugs across the rendering pipeline—covering matrix transformations, backface culling, barycentric coordinates, and depth testing—so that 3D assets render correctly.

## Rationale
**Why this task is valuable:**
- Tests deep knowledge of linear algebra and 3D computer graphics math (vectors, matrices, cross products).
- Requires understanding of the standard graphics rendering pipeline (Model -> View -> Projection -> Viewport).
- Exercises spatial reasoning and ability to map visual artifacts (e.g., inside-out models, upside-down renders, overlapping faces) to specific mathematical errors in code.

**Real-world Context:** A technical director at an animation studio is trying to use a lightweight, headless Python software rasterizer to automatically generate preview thumbnails for 3D assets on a server farm. However, the rasterizer is currently producing distorted, inside-out, and upside-down images. The pipeline must be fixed before the nightly batch job runs.

## Task Description

**Goal:** Find and fix all 5 math and logic bugs in the 3D software rasterizer pipeline so that it correctly renders `.obj` files to image files.

**Starting State:** VS Code is open with the workspace `/home/ga/workspace/tiny_rasterizer/` loaded. The project contains a Python rasterizer, a test script (`render.py`), and a directory of 3D `.obj` files (`assets/`). Running `python render.py` currently produces a mangled `output.png`.

**Expected Actions:**
The agent must fix the following 5 specific issues across the codebase:

1. **Backface Culling (`rasterizer.py`)**: The cross product used to calculate the surface normal of a triangle has the wrong winding order, causing front-facing triangles to be culled instead of back-facing ones.
2. **Z-Buffer / Depth Test (`rasterizer.py`)**: The depth test condition is reversed. It currently overwrites pixels if the new Z value is *further* away, causing background triangles to render on top of foreground triangles.
3. **Perspective Divide (`camera.py`)**: The perspective divide step (`x/w`, `y/w`, `z/w`) fails to divide the `z` coordinate by `w`, corrupting depth interpolation and perspective correctness.
4. **Barycentric Coordinates (`geometry.py`)**: The determinant calculation for barycentric coordinates mixes up the X and Y components of the vertices, causing severe texture and interpolation distortion across faces.
5. **Viewport Transformation (`camera.py`)**: The viewport matrix maps Normalized Device Coordinates (NDC) to screen space, but fails to invert the Y-axis. Since NDC Y points up and image coordinates Y points down, the resulting image is rendered upside down.

**Final State:** All 5 bugs are fixed. Running `python render.py` produces a visually correct `output.png` of a 3D Torus with proper depth, orientation, and surface culling.

## Verification Strategy

### Primary Verification: Programmatic Math Validation (Hidden Test Suite)
The verifier runs a hidden `pytest`-style suite that imports the agent's modified modules and tests the mathematical correctness of each function in isolation:
- `test_normal_calculation`: Injects a known triangle and verifies normal vector direction.
- `test_zbuffer_logic`: Feeds overlapping fragments and verifies only the closest survives.
- `test_perspective_divide`: Verifies full division by `w`.
- `test_barycentric`: Asserts correct weights `(u, v, w)` for a point inside a test triangle.
- `test_viewport_matrix`: Verifies the resulting 4x4 viewport matrix has the correct negative scaling on the Y-axis.

### Secondary Verification: Output File Validation (Anti-gaming)
Checks if `output.png` exists and was genuinely modified during the task interval.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Fix Backface Culling | 20 | `test_normal_calculation` passes |
| Fix Depth Test | 20 | `test_zbuffer_logic` passes |
| Fix Perspective Divide | 20 | `test_perspective_divide` passes |
| Fix Barycentric Math | 20 | `test_barycentric` passes |
| Fix Viewport Transform | 20 | `test_viewport_matrix` passes |
| **Total** | **100** | |

**Pass Threshold:** 60 points (3 of 5 bugs fixed) AND output file updated.