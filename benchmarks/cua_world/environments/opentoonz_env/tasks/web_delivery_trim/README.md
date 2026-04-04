# web_delivery_trim

## Overview

**Domain**: Animation / Web Content Delivery
**Difficulty**: very_hard
**Occupation**: Animation Supervisor / Web Media Producer

An animation supervisor needs to deliver a trimmed loop version of a walk cycle for web use. Web delivery typically requires shorter, optimized content — a single complete gait cycle of 16 frames rather than the full scene. The output must be at 720p (1280×720) for web delivery pipelines, not full HD.

## Goal

Open `/home/ga/OpenToonz/samples/dwanko_run.tnz` in OpenToonz. Render **only frames 1 through 16** (a single gait cycle) at **1280×720 resolution** as PNG frames to `/home/ga/OpenToonz/output/web_trim/`. The delivery must contain exactly this frame range (14–20 frames accepted) at 720p resolution.

## Real Data Source

- **dwanko_run.tnz**: Official OpenToonz sample walk cycle from the OpenToonz GitHub repository.

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Frame count 14–20 | 30 | Correct frame range rendered (not full scene) |
| Resolution 1280×720 | 30 | 720p web delivery resolution |
| Files newer than task start | 25 | Rendered during this task session |
| Total output size ≥ 100 KB | 15 | Substantial content |

**Pass threshold**: 60/100 points

## Application Features Required

1. **Scene loading** — Open dwanko_run.tnz
2. **Frame range selection** — Configure render to output only frames 1–16 (not the full scene)
3. **Output resolution** — Set render resolution to 1280×720 (720p, distinct from HD 1080p)
4. **Render to disk** — Export PNG sequence with specific start/end frame settings

## Why This Is Hard

The agent must:
1. Find OpenToonz's frame range render controls (often in Output Settings or Render dialog)
2. Set both start frame AND end frame correctly to limit output to 16 frames
3. Set the correct 720p resolution (not 1080p, not PAL SD)
4. Understand that the task requires a specific SUBSET of frames, not the full animation

Frame range control is a distinct capability from simply rendering the whole scene — it requires the agent to discover and correctly configure additional parameters.

## Starting State

- Output directory `/home/ga/OpenToonz/output/web_trim/` is empty
- `dwanko_run.tnz` present at expected path
- OpenToonz running

## Verification Strategy

`export_result.sh`:
- Counts PNG files in output dir
- Gets image dimensions via PIL
- Checks file modification times vs task start
- Measures total size

`verifier.py`: Awards full frame-count credit for 14–20 frames (flexibility for off-by-one in frame numbering), awards resolution credit only for exact 1280×720.

## Notes

- The frame count check accepts 14–20 frames (allows slight variation in how OpenToonz counts frame numbers, e.g., 0-indexed vs 1-indexed)
- Full credit requires being in the correct range — rendering all 24+ frames would not qualify
