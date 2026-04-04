# animation_mp4_export

## Overview

**Domain**: Animation / Post-Production Delivery
**Difficulty**: very_hard
**Occupation**: Post-Production Coordinator (Animation Studio)

A post-production coordinator needs to export an animation as a single deliverable video file rather than an image frame sequence. This uses a completely different export workflow in OpenToonz — video rendering vs. PNG sequence rendering.

## Goal

Open `/home/ga/OpenToonz/samples/dwanko_run.tnz` in OpenToonz and export the complete animation as a **video file** (MP4, MOV, AVI, or other video format) to `/home/ga/OpenToonz/output/video_export/`. The video must be a valid, playable file containing the animation.

## Real Data Source

- **dwanko_run.tnz**: Official OpenToonz sample animation from the OpenToonz GitHub repository.

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Video file exists | 30 | A video file found in output_dir |
| File size ≥ 50 KB | 30 | Not an empty or stub file |
| File created after task start | 25 | Rendered during this session |
| Valid video (ffprobe readable) | 15 | Playable video with detectable duration |

**Pass threshold**: 60/100 points

## Application Features Required

1. **Scene loading** — Open dwanko_run.tnz
2. **Video export / Render to video** — OpenToonz's video output mode (different from PNG sequence)
3. **Codec and container selection** — Select MP4/MOV/AVI container format
4. **Output path configuration** — Specify output directory and filename

## Why This Is Hard

Video export in OpenToonz uses a distinct workflow from PNG sequence rendering. The agent must:
1. Discover that there is a separate video export capability in OpenToonz
2. Navigate to the correct dialog/menu (not just the standard "Render" PNG sequence path)
3. Configure codec and output path
4. Execute the export

This is meaningfully different from the walkcycle_hd_render and pal_broadcast_delivery tasks, which produce PNG sequences.

## Starting State

- Output directory `/home/ga/OpenToonz/output/video_export/` is empty
- No pre-existing video files
- OpenToonz is running

## Verification Strategy

`export_result.sh`:
- Searches for video files (mp4, mov, avi, webm, mkv) in output_dir
- Checks file size
- Checks mtime vs task start
- Attempts ffprobe to extract duration

`verifier.py`: Awards points for video file existence, size, newness, and ffprobe validity.
