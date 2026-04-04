# pal_broadcast_delivery

## Overview

**Domain**: Television Animation / European Broadcast Production
**Difficulty**: very_hard
**Occupation**: Technical Director (Animation Studio)

A technical director preparing content for European broadcast must convert a scene from NTSC settings to PAL broadcast specifications. PAL is the standard used in Europe, Australia, and much of Asia — 720×576 pixels at 25fps — distinct from NTSC (typically 720×480 or other resolutions at 24/29.97fps).

## Goal

Open `/home/ga/OpenToonz/samples/dwanko_run.tnz` in OpenToonz. The scene is configured with NTSC-compatible settings. Reconfigure it for **PAL broadcast**: set the output resolution to **720×576** and the frame rate to **25 fps**. Render at least **25 PNG frames** to `/home/ga/OpenToonz/output/pal_delivery/`.

## Real Data Source

- **dwanko_run.tnz**: Official OpenToonz sample walk cycle from the OpenToonz GitHub repository. A real animation file used across OpenToonz documentation and tutorials.

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Frame count ≥ 25 | 25 | At least 25 PNG frames exported |
| Resolution 720×576 | 35 | Frames at PAL SD resolution |
| Files newer than task start | 25 | Frames were rendered during this task session |
| Total output size ≥ 150 KB | 15 | Substantial rendered content |

**Pass threshold**: 60/100 points

## Application Features Required

1. **Scene loading** — Open dwanko_run.tnz
2. **Scene/camera settings** — Change output resolution to 720×576 (PAL SD)
3. **Frame rate configuration** — Set scene FPS to 25
4. **Render to disk** — Export PNG frame sequence to specified directory

## Starting State

- Output directory `/home/ga/OpenToonz/output/pal_delivery/` is empty
- `dwanko_run.tnz` has non-PAL settings
- OpenToonz is running

## Why This Is Hard

The agent must:
1. Understand that "PAL" implies specific resolution and frame rate standards
2. Find the scene settings (camera, FPS) in OpenToonz's UI without being told which menu
3. Correctly input 720×576 and 25fps (not just any resolution)
4. Set the output path and render

## Verification Strategy

`export_result.sh`:
- Counts PNG files in /home/ga/OpenToonz/output/pal_delivery/
- Uses PIL to get image dimensions of first frame
- Checks file modification times vs task start
- Measures total output size

`verifier.py`: Applies multi-criterion scoring with 720×576 dimension check as primary discriminator.
