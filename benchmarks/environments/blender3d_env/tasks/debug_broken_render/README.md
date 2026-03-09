# debug_broken_render

## Domain Context

Debugging broken renders is a routine task for technical artists and pipeline TDs. A scene file arrives from a colleague or automated pipeline that produces an incorrect output -- black frames, missing objects, wrong resolution, or camera pointing into empty space. The artist must systematically inspect scene settings, identify each misconfiguration, and fix them before re-rendering. This requires knowledge of Blender's camera system, lighting, render settings, and object visibility flags.

## Task Goal

The agent starts with a Blender scene that has 5 intentional bugs planted by the setup script. The baseline scene (a red cube on a ground plane with sun lighting) should produce a clean render, but the broken version produces a tiny, black, empty image. The agent must:

1. **Fix the camera** -- it has been rotated to face away from the scene (Track To constraint removed)
2. **Fix the lighting** -- sun light energy is set to 0.0 (completely dark)
3. **Fix the resolution** -- render resolution is set to 10x10 pixels (unusable)
4. **Fix the samples** -- Cycles render samples set to 1 (extremely noisy)
5. **Fix object visibility** -- the main cube has `hide_render = True` (invisible in renders)
6. **Render the corrected scene** and save to `/home/ga/BlenderProjects/fixed_render.png`
7. **Save the project** to `/home/ga/BlenderProjects/fixed_scene.blend`

## Starting State

- `broken_scene.blend` loaded in Blender with all 5 bugs active
- Camera pointing away from the scene (no tracking constraint)
- Sun light energy = 0.0
- Render resolution = 10x10
- Cycles samples = 1
- BaseCube has hide_render = True
- No output files exist
- Blender is open and maximized

## Scoring (100 points)

| Subtask | Points | Criterion |
|---------|--------|-----------|
| Camera faces scene | 15 | Camera forward vector has positive dot product toward scene center, or has a tracking constraint |
| Light energy fixed | 15 | SunLight energy > 0.5 |
| Resolution fixed | 15 | Render resolution >= 1280x720 |
| Samples fixed | 10 | Cycles samples >= 16 |
| BaseCube visible | 15 | BaseCube.hide_render is False |
| Render output saved | 15 | fixed_render.png exists, is valid PNG, reasonable size |
| Blend file saved | 15 | fixed_scene.blend exists at expected path |

## Pass Threshold

Score >= 70 (must fix the majority of bugs and produce output files).

## Verification Strategy

The export_result.sh script uses Blender Python (headless) to inspect the saved blend file and extract:
- Camera direction (forward vector dot product toward origin)
- Whether camera has a Track To constraint
- Sun light energy value
- Render resolution X and Y
- Cycles render samples
- BaseCube hide_render flag
- Object list

The verifier reads `/tmp/task_result.json` and scores each criterion independently.

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task definition, metadata, hooks, success criteria |
| `setup_task.sh` | Plants 5 bugs in baseline scene, launches Blender with broken scene |
| `export_result.sh` | Analyzes saved blend file and render output, writes `/tmp/task_result.json` |
| `verifier.py` | Reads task_result.json, scores 7 criteria, returns pass/fail |
| `README.md` | This file |
