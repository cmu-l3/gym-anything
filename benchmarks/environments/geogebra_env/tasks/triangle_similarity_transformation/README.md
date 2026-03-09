# Task: Triangle Similarity Transformation Proof

## Overview

**Difficulty**: Hard
**Occupation**: Secondary School Teacher (Geometry, Common Core)
**Timeout**: 480 seconds, 60 max steps

A high school geometry teacher creating an interactive proof demonstration for the SAS Triangle Similarity Theorem (Common Core Standard G-SRT.5). This is a genuine professional workflow — GeoGebra is widely used in US and international high school geometry courses to provide dynamic, interactive proof demonstrations.

## What Makes This Hard

1. **Dilation tool is non-obvious**: The Dilate transformation in GeoGebra requires knowing to use `Transform > Dilate From Point` or the input bar command `Dilate(object, factor, center)`. Most users think of stretching or scaling, not "dilation."
2. **Must use the CORRECT geometric tool** (Dilate command), not manually calculate and place the dilated vertices — the verifier checks for the Dilate command specifically.
3. **Multiple required elements**: polygon, dilation transform, 6 side length measurements, text annotation.
4. **Precision required**: Vertices must be at exact coordinates.
5. **Verification of ratios**: The annotation must explicitly state the scale factor.

## Goal (End State)

A file `triangle_similarity.ggb` in `~/Documents/GeoGebra/projects/` containing:
- Triangle ABC with A=(0,0), B=(4,0), C=(2,3) — constructed using the Polygon tool
- Triangle A'B'C' as a dilation of ABC by scale factor 1.5 from the origin — created using `Dilate(poly, 1.5, A)` or equivalent
- Measurements of the 6 side lengths: AB=4, BC=√13≈3.606, AC=√13≈3.606, A'B'=6, B'C'=5.408, A'C'=5.408
- Text annotation confirming similarity (scale factor 1.5, equal ratios)

## Mathematical Background

**Original triangle ABC**:
- A = (0, 0)
- B = (4, 0)
- C = (2, 3)
- AB = 4
- BC = √((4-2)² + (0-3)²) = √(4+9) = √13 ≈ 3.606
- AC = √((0-2)² + (0-3)²) = √(4+9) = √13 ≈ 3.606  (isoceles triangle!)

**Dilated triangle A'B'C' (scale 1.5, center origin)**:
- A' = 1.5 × (0,0) = (0, 0)  — same as A (center is A itself)
- B' = 1.5 × (4,0) = (6, 0)
- C' = 1.5 × (2,3) = (3, 4.5)
- A'B' = 6 = 1.5 × AB ✓
- B'C' = √13 × 1.5 ≈ 5.408 = 1.5 × BC ✓
- A'C' = √13 × 1.5 ≈ 5.408 = 1.5 × AC ✓

All angle pairs are equal (AA similarity), all side ratios equal 1.5 → triangles are similar.

## Verification Criteria (100 points total)

| Criterion | Points | How Checked |
|-----------|--------|-------------|
| File created during task | 20 | mtime ≥ task start |
| Original vertices A(0,0), B(4,0), C(2,3) | 20 | Point elements within ±0.15 tolerance |
| Dilate command used | 20 | `<command name="Dilate">` in XML |
| Dilated triangle at B'(6,0), C'(3,4.5) | 20 | Point elements within ±0.15 (partial credit for 1/2) |
| Measurements + text annotation | 20 | Segment/numeric elements + text element |

**Pass threshold**: 70 points

## GeoGebra Commands

```
A = (0, 0)
B = (4, 0)
C = (2, 3)
triangle_ABC = Polygon(A, B, C)
triangle_ABC_prime = Dilate(triangle_ABC, 1.5, A)
# Then add Distance measurements: Distance(A,B), Distance(B,C), etc.
# Then add Text with scale factor confirmation
```
