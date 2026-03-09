# Studio Product Lighting

## Domain Context

Professional product visualization is a core workflow in automotive marketing, e-commerce, and industrial design. A product photographer or 3D visualization specialist receives a raw model and must set up studio-quality lighting that reveals form, material properties, and brand appeal. The standard approach is a **3-point lighting setup**: a dominant key light, a softer fill light to reduce shadows, and a rim/back light to separate the subject from the background. Area and spot lights are the professional choices because they produce soft, controllable illumination compared to point lights.

## Task Goal

The agent starts with the BMW27 demo scene in Blender, but **all lights have been removed** and the world background has been set to default grey. The agent must:

1. **Create a 3-point lighting setup** -- at least 3 lights of type AREA or SPOT
2. **Position the camera** for a classic automotive 3/4 front view (height 0.5-3m, angled)
3. **Set the world background** to a dark studio color (near black, brightness < 0.15)
4. **Render the scene** and save to `/home/ga/BlenderProjects/product_shot.png`
5. **Save the project** to `/home/ga/BlenderProjects/studio_setup.blend`

## Starting State

- BMW27.blend loaded with all LIGHT objects deleted
- World background color set to grey (0.5, 0.5, 0.5) -- not studio-appropriate
- Camera exists but at default position
- No render output files exist
- Blender is open and maximized

## Verification Strategy

### Subtask Scoring (100 points total)

| Subtask | Points | Signal Source | Criterion |
|---------|--------|---------------|-----------|
| 3+ studio lights | 25 | export_result.sh scene analysis | >= 3 lights of type AREA or SPOT |
| Camera position | 20 | export_result.sh scene analysis | Camera height in [0.5, 3.0]m, not at origin |
| Dark world background | 15 | export_result.sh scene analysis | World color brightness < 0.15 |
| Render output | 25 | export_result.sh file check + VLM | PNG exists, >100KB, VLM confirms lit car |
| Blend file saved | 15 | export_result.sh file check | Valid .blend at expected path |

### Pass Threshold

Score >= 70 (lights setup + at least one other major subtask).

### VLM Verification (Bonus)

If `query_vlm` is available, the rendered image is checked for:
- Visible car/vehicle with studio lighting
- Multiple distinct light sources (highlights, reflections)
- Dark/black background typical of studio photography

## Ground Truth

A correct solution will have:
- 3+ AREA or SPOT lights positioned around the car (key ~45deg front-side, fill opposite side, rim behind)
- Camera at roughly `(6, -6, 2)` or similar 3/4 view, aimed at the car center
- World background RGB near `(0.0, 0.0, 0.0)` or `(0.05, 0.05, 0.05)`
- A rendered PNG showing the BMW with visible lighting, reflections, and dark backdrop
- The .blend file saved with all modifications

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task definition, metadata, hooks, success criteria |
| `setup_task.sh` | Strips lights from BMW scene, sets grey world, launches Blender |
| `export_result.sh` | Analyzes saved blend file and render output, writes `/tmp/task_result.json` |
| `verifier.py` | Reads task_result.json, scores 5 criteria, returns pass/fail |
| `README.md` | This file |
