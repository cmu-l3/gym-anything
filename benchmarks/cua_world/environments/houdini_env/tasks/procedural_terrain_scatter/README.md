# procedural_terrain_scatter

## Overview

**Occupation**: VFX Environment Artist
**Difficulty**: very_hard
**Pattern**: Creation from scratch (empty scene)

A VFX environment artist builds a complete procedural mountain terrain with erosion, scattered rock instances, HDRI lighting, and a final render — all from an empty Houdini scene.

## Goal

Create a photorealistic procedural mountain environment in Houdini:
- A HeightField-based terrain with thermal and/or hydraulic erosion
- At least 50 scattered rock/object instances on the terrain surface
- HDRI environment lighting for outdoor illumination
- A camera framing the terrain
- A 1920x1080 rendered image

The agent must build everything from scratch — no pre-built scene is provided.

## Success Criteria

| Criterion | Points | Key |
|-----------|--------|-----|
| Output scene exists and > 10KB | 10 | `scene_exists`, `scene_size_bytes` |
| HeightField terrain node(s) present | 15 | `has_heightfield` |
| Erosion applied (thermal/hydraulic) | 15 | `has_erosion` |
| Scatter/CopyToPoints with >= 50 instances | 10 + 5 | `has_scatter_or_copy`, `scatter_point_count` |
| Material(s) assigned | 10 | `has_material` |
| HDRI environment light with path | 10 | `has_env_light` |
| Camera in scene | 5 | `has_camera` |
| Render node configured | 5 | `has_render_node` |
| Render image exists and > 50KB | 15 | `render_exists`, `render_size_bytes` |
| **Total** | **100** | |
| **Pass threshold** | **60** | |

## Verification Strategy

`export_result.sh` uses hython to load the saved scene and traverse `/obj` recursively, checking node types for HeightField, erosion, scatter/copy, envlight, cam, and render nodes. It also inspects `/mat` for materials and `/out` for render ROPs.

## Starting State

- Empty Houdini scene (no pre-built geometry)
- Meadow HDRI downloaded to `/home/ga/HoudiniProjects/data/meadow_1k.hdr`
- Teapot.obj available as potential scatter source geometry

## Features Used

HeightField terrain, Erosion SOPs, Scatter/CopyToPoints, Environment Light (HDRI), Camera, Mantra/Karma ROP, Materials

## Edge Cases

- Agent may use different erosion node types (HeightField Erode vs custom)
- Rock geometry may be procedural rather than imported OBJ
- Scatter count is checked on the output of copy/scatter nodes
