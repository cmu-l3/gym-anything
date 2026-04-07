# 2-Way Speaker Baffle CNC Layout (`speaker_baffle_cnc_layout@1`)

## Overview
This task evaluates the agent's ability to create a precision 2D layout in SolveSpace by combining primitive geometric shapes (rectangles and circles) and applying relational dimensional constraints. The agent must position internal features (driver cutouts) accurately relative to each other and to the outer boundary, which is a fundamental skill for CNC routing and laser cutting workflows.

## Rationale
**Why this task is valuable:**
- Tests relational dimensioning (e.g., constraining the distance between two circle centers, or a center to an edge), which is more advanced than just dimensioning a single shape's size.
- Evaluates the agent's ability to combine different geometry types (lines forming a rectangle, and standalone circles) in a single sketch.
- Requires using alignment constraints (vertical alignment of centers) to ensure symmetry.
- Validates the agent's understanding of radius vs. diameter when applying size constraints to circles.
- Represents a highly common, real-world 2D CAD workflow (preparing flat panels for subtractive manufacturing).

**Real-world Context:** An audiophile hobbyist is building a custom set of 2-way bookshelf speakers. They need to CNC route the front wooden baffle to exact specifications so the speaker drivers fit flush. The CAD layout must have precise cutouts for a 6.5" woofer and a 1" dome tweeter, with their acoustic centers perfectly aligned and spaced to prevent phase interference.

## Task Description

**Goal:** Create a fully constrained 2D sketch of a rectangular speaker baffle with two vertically aligned circular cutouts, and save it to `~/Documents/SolveSpace/speaker_baffle.slvs`.

**Starting State:** SolveSpace is open with a blank new sketch on the default `sketch-in-plane` workplane. The working directory `~/Documents/SolveSpace/` exists and is empty.

**Expected Actions:**
1. Draw a rectangular outer boundary. Apply horizontal/vertical constraints to the lines, and set the dimensions to **200 mm wide** and **350 mm tall**.
2. Draw a circle for the tweeter cutout (upper circle) with a diameter of **75 mm** (or a radius of 37.5 mm).
3. Draw a circle for the woofer cutout (lower circle) with a diameter of **145 mm** (or a radius of 72.5 mm).
4. Apply geometric constraints to ensure both circle centers are vertically aligned with the horizontal center of the rectangle (i.e., they lie on the vertical centerline of the board).
5. Add a distance constraint between the tweeter's center point and the top horizontal edge of the rectangle, setting it to exactly **80 mm**.
6. Add a distance constraint between the tweeter's center point and the woofer's center point, setting it to exactly **130 mm**.
7. Confirm the sketch is constrained properly (the circles should be positioned as an upper smaller hole and a lower larger hole).
8. Save the layout to `/home/ga/Documents/SolveSpace/speaker_baffle.slvs`.

**Final State:** A valid SolveSpace file exists at the target path containing a 200x350 rectangle and two circles (75mm and 145mm diameters) spaced perfectly according to the dimensional requirements.

## Verification Strategy

### Primary Verification: Parametric File Parsing (Programmatic)
The SolveSpace `.slvs` file format is human-readable. A Python script will parse the saved file to verify the exact dimensional and geometric parameters:
1. **Entity Verification**: Search for `Request.type=400` (Circle) to ensure exactly 2 circles exist, and `Entity.type=11000` (Line segment) to ensure at least 4 lines exist.
2. **Dimension Verification**: Extract all floating-point values from `Param.val=` fields. The file must contain values matching (within ±0.5 tolerance):
   - `200.0` (Width)
   - `350.0` (Height)
   - `80.0` (Top edge to tweeter center distance)
   - `130.0` (Tweeter center to woofer center distance)
3. **Diameter/Radius Verification**: Check the `Param.val` fields for the circle sizes. The script will accept either diameter values (`75.0` and `145.0`) or radius values (`37.5` and `72.5`).

### Secondary Verification: VLM Visual & Anti-Gaming Checks
- **Anti-Gaming**: Check the modification timestamp of the `.slvs` file against the task start time to ensure the file was actively created by the agent, not pre-existing.
- **Visual Verification**: A VLM reviews a trajectory of screenshots to confirm the visual layout: a tall rectangle with a smaller circle positioned near the top, and a larger circle positioned below it, vertically aligned.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| File Created | 15 | `speaker_baffle.slvs` exists and is a valid SolveSpace file. |
| Time Validity | 10 | File was created after the task started. |
| Outer Dimensions | 15 | File parameters contain 200.0 and 350.0 for the rectangle. |
| Cutout Sizes | 15 | File parameters contain 75.0/145.0 (dia) or 37.5/72.5 (rad). |
| Positional Dimensions| 15 | File parameters contain 80.0 and 130.0 for the layout spacing. |
| Entity Count | 10 | Exactly 2 circles and >=4 line segments are present in the file. |
| VLM Layout | 20 | Visual confirmation of layout via trajectory frames. |
| **Total** | **100** | |

**Pass Threshold:** 70 points, which MUST include the File Created, Outer Dimensions, Cutout Sizes, and Positional Dimensions criteria.