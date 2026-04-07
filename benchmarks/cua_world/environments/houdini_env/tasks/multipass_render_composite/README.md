# multipass_render_composite

## Overview

**Occupation**: Lighting Technical Director
**Difficulty**: very_hard
**Pattern**: Enhancement of pre-built scene

A Lighting TD takes a pre-lit scene and configures multi-pass AOV rendering with Mantra, then builds a COP2 compositing network to combine the passes.

## Goal

Starting from a scene with a teapot, materials, and lighting already set up:
1. Configure Mantra with extra image planes (AOVs) for at least 4 render passes
2. Render the passes as separate EXR files
3. Build a COP2 compositing network at `/img` to load and recombine the passes
4. Output a final composite EXR

## Success Criteria

| Criterion | Points | Key |
|-----------|--------|-----|
| Output scene exists and > 10KB | 5 | `scene_exists`, `scene_size_bytes` |
| Mantra has extra image planes (>= 4) | 10 | `num_extra_planes` |
| AOV: direct_diffuse | 8 | `extra_plane_variables` |
| AOV: indirect_diffuse | 8 | `extra_plane_variables` |
| AOV: direct_specular | 8 | `extra_plane_variables` |
| AOV: emission | 8 | `extra_plane_variables` |
| Rendered pass files exist | 8 | `pass_files_count` |
| COP2 network with >= 2 nodes | 15 | `cop_network_exists`, `cop_node_count` |
| COP has file input nodes (>= 2) | 10 | `cop_has_file_nodes` |
| COP has merge/composite node | 10 | `cop_has_merge_or_composite` |
| Final composite exists and > 10KB | 10 | `composite_exists`, `composite_size_bytes` |
| **Total** | **100** | |
| **Pass threshold** | **60** | |

## Partial Credit Check (Anti-Pattern 4)

Max partial total = 2 (scene small) + partial_planes(up to 6) + 0*4 + 0 + 8 (COP 1 node) + 5 (COP 1 file node) + 0 + 5 (composite small) = **26 < 60 threshold**

## Verification Strategy

`export_result.sh` uses hython to inspect the Mantra node's `vm_numaux` parameter and `vm_variable_plane` entries, then checks `/img` for COP2 network structure and node types.

## Starting State

- Pre-lit scene with teapot, blue ceramic material, key/fill/env lights, Venice Sunset HDRI
- Camera and basic Mantra node configured (no AOVs)
- No COP2 network exists — agent must create it

## Do-Nothing Baseline

Scene exists (~5 pts for scene) but no AOVs, no COP network → ~5 pts, `passed=False`.

## Features Used

Mantra ROP, Extra Image Planes (AOVs), COP2 Network, File COP, Composite/Merge COP, ROP Output Driver
