# classroom_material_overhaul

## Overview

A hard-difficulty Blender 3D task where the agent must fix four corrupted materials
in a classroom scene. The official Blender demo classroom scene is loaded with four
key materials (floor, wall, desk/table, glass/window) deliberately reset to flat grey.
The agent must re-create realistic materials for each surface and save the result.

## Task Description

An interior designer receives a 3D classroom visualization where four materials have
been corrupted to flat grey:

1. **Floor** -- should be polished wooden flooring (warm brown, moderate roughness)
2. **Wall** -- should be a clean painted wall (light/white color)
3. **Desk/Table** -- should be wooden furniture (natural brown tone)
4. **Glass/Window** -- should be transparent glass (transmission > 0.5)

The agent must use the Blender Shader Editor or material properties to fix each
material and save the corrected scene to `/home/ga/BlenderProjects/classroom_fixed.blend`.

## Scoring (100 points)

| Subtask | Points | Criterion |
|---------|--------|-----------|
| Floor material | 25 | Brown/wood base color + roughness in 0.3--0.7 |
| Wall material | 20 | Light/white base color (RGB each >= 0.7) |
| Desk material | 20 | Wood-like brown base color |
| Glass material | 20 | Transmission > 0.5 |
| File saved | 15 | classroom_fixed.blend exists and is valid |

Pass threshold: 70 points.

## Files

- `task.json` -- task definition and metadata
- `setup_task.sh` -- pre-task hook: breaks 4 materials, launches Blender
- `export_result.sh` -- post-task hook: extracts material properties from saved file
- `verifier.py` -- programmatic scorer

## Material Detection

The setup script searches material names (case-insensitive) for keywords:
- Floor: "floor", "wood_floor", "parquet"
- Wall: "wall", "paint", "plaster"
- Desk: "desk", "table", "furniture"
- Glass: "glass", "window", "transparent"

The exact material names found are recorded in `/tmp/initial_state.json` and propagated
through export_result.sh into `/tmp/task_result.json` so the verifier does not rely on
hardcoded names.
