# procedural_building_hda

## Overview

**Occupation**: Pipeline Technical Director
**Difficulty**: very_hard
**Pattern**: Specification-driven discovery

A Pipeline TD reads a specification document from the Desktop and creates a Houdini Digital Asset (HDA) that meets all documented requirements, then builds a test scene demonstrating parameter variations.

## Goal

1. Read the spec document at `/home/ga/Desktop/building_hda_spec.txt`
2. Create an HDA that procedurally generates buildings with the required parameters
3. Ensure the HDA produces valid geometry with UVs
4. Create a test scene with at least 3 instances using different parameter values
5. Demonstrate that parameters actually affect the output geometry

## Success Criteria

| Criterion | Points | Key |
|-----------|--------|-----|
| HDA file exists and > 1KB | 10 | `hda_exists`, `hda_size_bytes` |
| HDA installs successfully | 5 | `hda_installs` |
| Has building_width parameter | 8 | `has_building_width` |
| Has building_height parameter | 8 | `has_building_height` |
| Has num_floors parameter | 8 | `has_num_floors` |
| Has window_density parameter | 8 | `has_window_density` |
| Geometry poly count in 500-50000 | 8 | `default_poly_count` |
| Geometry has UVs | 8 | `default_has_uvs` |
| Test scene exists | 5 | `scene_exists` |
| At least 3 HDA instances | 10 | `instance_count` |
| Instances have different params | 7 | `instance_params` |
| Poly count varies with num_floors | 8 | `poly_count_varies_with_floors` |
| Height varies with building_height | 7 | `height_varies_with_param` |
| **Total** | **100** | |
| **Pass threshold** | **60** | |

## Partial Credit Check (Anti-Pattern 4)

Max partial total = 3 (HDA small) + 0 + 0*4 + 3 (poly out of range) + 0 + 0 + 6 (2/3 instances) + 0 + 0 + 0 = **12 < 60 threshold**

## Verification Strategy

`export_result.sh` uses hython to:
1. Install the HDA and check for required parameter templates
2. Create a default instance and measure geometry (poly count, UVs, bounding box)
3. Create instances with varied `num_floors` and `building_height` to verify parameter responsiveness
4. Load the test scene and count HDA instances with their parameter values

## Starting State

- Empty Houdini scene (no pre-built content)
- Spec document placed on Desktop
- HDA output directory created but empty

## Do-Nothing Baseline

No HDA file, no test scene → 0 pts, `passed=False`.

## Features Used

HDA Creation (Subnet → Digital Asset), Parameter Interface, SOP Geometry Generation, UV Generation, Scene Instancing, Parameter Templates
