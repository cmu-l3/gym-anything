# walkcycle_hd_render

## Overview

**Domain**: Television Animation / Broadcast Production
**Difficulty**: very_hard
**Occupation**: Production Animator (TV Studio)

A production animator at a TV studio needs to render a character walk cycle animation to the broadcast-standard HD format. The animator must use OpenToonz to set the correct render resolution and export the animation as individual PNG frames for the broadcast pipeline.

## Goal

Open the walk cycle scene `/home/ga/OpenToonz/samples/dwanko_run.tnz` in OpenToonz, configure the output settings to render at **1920×1080 HD resolution**, and render a PNG frame sequence of at least **24 frames** to `/home/ga/OpenToonz/output/walkcycle_hd/`.

## Real Data Source

- **dwanko_run.tnz**: Official OpenToonz sample file downloaded from the OpenToonz GitHub repository (`https://github.com/opentoonz/opentoonz/blob/master/stuff/samples/`). This is a real walk cycle animation included as part of the OpenToonz distribution.

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Frame count ≥ 24 | 25 | At least 24 PNG frames exported |
| Resolution 1920×1080 | 30 | All frames at HD resolution |
| Files newer than task start | 25 | Frames were rendered during the task (not pre-existing) |
| Total output size ≥ 300 KB | 20 | Substantial rendered content |

**Pass threshold**: 60/100 points

## Application Features Required

1. **Scene loading** — Open an existing .tnz scene file
2. **Output settings / Render resolution** — Configure the render output resolution to 1920×1080
3. **Render to disk** — Render the scene as a PNG frame sequence using OpenToonz's render pipeline
4. **Output path configuration** — Set the output directory to the specified path

## Starting State

- Output directory `/home/ga/OpenToonz/output/walkcycle_hd/` is empty
- `dwanko_run.tnz` is present at `/home/ga/OpenToonz/samples/dwanko_run.tnz`
- OpenToonz is running

## Verification Strategy

`export_result.sh` runs inside the VM and:
1. Counts PNG/TGA files in the output directory
2. Reads first image dimensions using PIL
3. Counts files with mtime newer than task start timestamp
4. Measures total output directory size

`verifier.py` reads the exported JSON and applies multi-criterion scoring.

## Notes

- OpenToonz can render as PNG or TGA sequences — both are accepted
- The scene has a finite number of animation frames (≥24)
- The agent must discover how to set render resolution in OpenToonz's UI (not described here — this is a very_hard task)
