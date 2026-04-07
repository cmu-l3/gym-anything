# vfx_plate_integration

## Overview

**Occupation**: VFX Compositor
**Difficulty**: very_hard
**Pattern**: Enhancement of pre-built scene

A VFX compositor takes a base scene with a 3D model and HDRI, then sets up materials, multi-pass rendering, and a full compositing pipeline to integrate the CG object over a real background plate.

## Goal

Starting from a scene with a Stanford Bunny and Venice Sunset HDRI:
1. Create a ground plane with a shadow catcher/matte material
2. Assign a reflective chrome material to the bunny
3. Set up Mantra with separate object and shadow render passes
4. Build a COP2 compositing network combining renders over the background plate
5. Output a final composite EXR

## Success Criteria

| Criterion | Points | Key |
|-----------|--------|-----|
| Output scene exists and > 10KB | 5 | `scene_exists`, `scene_size_bytes` |
| Ground plane geometry exists | 8 | `has_ground_plane` |
| Shadow catcher material (matte) | 12 | `has_shadow_catcher_material` |
| Shadow catcher assigned to ground | 5 | `ground_plane_has_material` |
| Chrome material (metallic > 0.5) | 10 | `has_chrome_material` |
| Chrome assigned to bunny | 5 | `bunny_has_material` |
| Mantra node with output path | 5 | `has_mantra_node`, `mantra_output_path` |
| Separate render passes configured | 10 | `has_separate_passes` |
| COP2 network with >= 3 nodes | 10 | `has_cop_network`, `cop_node_count` |
| COP references bg_plate.jpg | 5 | `cop_references_bg_plate` |
| COP has composite/merge ops | 5 | `cop_has_composite_op` |
| Rendered files in integration/ | 10 | `render_file_count` |
| Final composite exists and > 10KB | 10 | `composite_exists`, `composite_size_bytes` |
| **Total** | **100** | |
| **Pass threshold** | **60** | |

## Partial Credit Check (Anti-Pattern 4)

Max partial total = 2 (scene small) + 0 + 0 + 0 + 4 (metallic 0.3-0.5) + 0 + 2 (mantra no output) + 0 + 4 (COP 1-2 nodes) + 0 + 0 + 0 + 4 (composite small) = **16 < 60 threshold**

## Verification Strategy

`export_result.sh` uses hython to:
1. Inspect `/mat` for shadow catcher (matte properties) and chrome (metallic > 0.5) materials
2. Check `/obj` for ground plane geometry and material assignments on ground + bunny
3. Check `/out` for Mantra passes configuration and extra image planes
4. Check `/img` for COP2 network with file inputs referencing bg_plate and composite ops
5. Check render output directory for files and final composite

## Starting State

- Base scene with bunny OBJ imported and Venice Sunset HDRI on env light
- Camera and basic Mantra node (single output, no passes)
- No materials in `/mat`
- No ground plane
- No COP2 network
- Background plate (tonemapped from HDRI) at `/home/ga/HoudiniProjects/data/bg_plate.jpg`

## Do-Nothing Baseline

Scene exists (~5 pts for scene) but no materials, no ground plane, no COP → ~5 pts, `passed=False`.

## Features Used

Principled Shader (matte/chrome), Material Assignment, Ground Plane Geometry, Mantra ROP (multi-pass), COP2 Compositing, File COP, Composite/Over COP, Environment Light
