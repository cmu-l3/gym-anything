# Multi-Object Scene Assembly

## Domain Context

Material showcase scenes are a standard practice in 3D art and game development. Artists and technical directors create these scenes to demonstrate material libraries, test shader configurations, and present asset catalogs to clients. The workflow involves placing multiple primitive objects, assigning distinct materials with different base colors, arranging objects so they are visually separated, adding a ground plane for context, and ensuring proper lighting for a presentable result.

## Task Goal

The agent starts with a nearly empty Blender scene (only a camera and one Sun light). The agent must build a complete material showcase scene from scratch:

1. **Add 5 primitive mesh objects**: UV Sphere, Cube, Cylinder, Cone, and Torus
2. **Assign distinct materials**: Each of the 5 objects gets a unique named material with a different base color
3. **Arrange objects**: Spread them out in a row or grid so none overlap
4. **Add a ground plane**: A large flat Plane mesh underneath all objects
5. **Ensure 2+ lights**: At least 2 light sources for proper illumination
6. **Save the file**: Save to `/home/ga/BlenderProjects/showcase_scene.blend`

## Starting State

- Empty Blender scene with only a Camera at (7, -6, 5) and one Sun light at (5, 5, 10)
- No mesh objects exist
- No materials exist
- Blender is open and maximized with the empty scene loaded

## Verification Strategy

### Subtask Scoring (100 points total)

| Subtask | Points | Signal Source | Criterion |
|---------|--------|---------------|-----------|
| 5 primitive types present | 25 | export_result.sh mesh analysis | 5 pts each for Sphere, Cube, Cylinder, Cone, Torus |
| 5+ distinct materials | 25 | export_result.sh material analysis | 5+ materials with different base colors (RGB diff > 0.1) |
| Objects don't overlap | 15 | export_result.sh spacing analysis | Min pairwise distance between mesh objects > 1.5 |
| Ground plane exists | 10 | export_result.sh plane detection | Large flat mesh at low Z |
| 2+ lights | 10 | export_result.sh light count | >= 2 LIGHT objects in scene |
| Blend file saved | 15 | export_result.sh file check | Valid .blend at expected path |

### Pass Threshold

Score >= 70 (primitives + materials + at least one supporting subtask).

## Ground Truth

A correct solution will have:
- 5 mesh objects named variations of Sphere, Cube, Cylinder, Cone, Torus
- 5 materials with distinct base colors (e.g., red, blue, green, gold, purple)
- Objects spaced at least 2-3 units apart in a line or grid
- A ground Plane scaled large (e.g., 10x10) at Z=0 or below the objects
- 2 lights (the initial Sun light plus at least one more)
- The .blend file saved at the expected path

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task definition, metadata, hooks, success criteria |
| `setup_task.sh` | Creates empty scene with camera + light, launches Blender |
| `export_result.sh` | Analyzes saved blend file, writes `/tmp/task_result.json` |
| `verifier.py` | Reads task_result.json, scores 6 criteria, returns pass/fail |
| `README.md` | This file |
