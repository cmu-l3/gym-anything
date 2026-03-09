# background_composite_render

## Overview

**Domain**: Animation Layout / Compositing
**Difficulty**: very_hard
**Occupation**: Layout Artist (Animation Studio)

A layout artist must composite a character animation over a background to produce a complete shot. This task requires importing an external image file as a background layer in OpenToonz, arranging the layer ordering so the background appears behind the character, and rendering the composited result.

## Goal

Open `/home/ga/OpenToonz/samples/dwanko_run.tnz` in OpenToonz. A background image is available at `/home/ga/OpenToonz/backgrounds/scene_background.jpg`. Import this background image into the scene as a level, order it behind the character animation, and render at least **20 PNG frames** at **1920×1080** resolution to `/home/ga/OpenToonz/output/composite_frames/`.

## Real Data Sources

- **dwanko_run.tnz**: Official OpenToonz sample walk cycle animation (from OpenToonz GitHub)
- **scene_background.jpg**: Real background image downloaded from Studio Ghibli's official gallery (`https://www.ghibli.jp/gallery/chihiro050.jpg`). A production-quality painted background from the "Spirited Away" train scene — representative of the kind of background art used in professional 2D animation pipelines.

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Frame count ≥ 20 | 25 | At least 20 composite PNG frames exported |
| Resolution 1920×1080 | 30 | Full HD composite render |
| Files newer than task start | 25 | Rendered during this task session |
| Total output size ≥ 200 KB | 20 | Substantial composite content |

**Pass threshold**: 60/100 points

## Application Features Required

1. **Scene loading** — Open dwanko_run.tnz
2. **Image level import** — Import an external image file (JPEG/PNG) as an OpenToonz level
3. **Xsheet column ordering** — Arrange the background column behind the character animation column
4. **Render to disk** — Export composite PNG sequence at HD resolution

## Why This Is Hard

The agent must:
1. Discover how to import an external image file into an existing OpenToonz scene
2. Understand OpenToonz's layer/column ordering model (columns to the right are in front by default, or vice versa depending on view)
3. Correctly place the background behind the character animation
4. Set render resolution and output path
5. Execute the composite render

This requires combining scene manipulation (import + column ordering) with rendering — a more complex feature combination than simple single-pass renders.

## Starting State

- Background image pre-placed at `/home/ga/OpenToonz/backgrounds/scene_background.jpg`
- Output directory `/home/ga/OpenToonz/output/composite_frames/` is empty
- OpenToonz is running

## Verification Strategy

`export_result.sh`:
- Counts PNG files in output directory
- Gets image dimensions via PIL
- Checks file modification times vs task start
- Measures total output size

`verifier.py`: Awards points for frame count, HD resolution, newness, and size.

## Notes

The background image is a real Studio Ghibli production artwork image, freely available from the official Ghibli gallery website for educational and portfolio purposes. It represents realistic background art of the type used in professional animation pipelines.
