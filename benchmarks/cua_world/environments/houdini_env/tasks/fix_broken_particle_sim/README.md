# fix_broken_particle_sim

## Overview

**Occupation**: FX Technical Director
**Difficulty**: very_hard
**Pattern**: Error injection (4 seeded errors)

An FX TD receives a broken particle simulation scene and must diagnose and repair all issues to get the simulation running correctly.

## Goal

A particle simulation at `/home/ga/HoudiniProjects/broken_particles.hipnc` has multiple errors preventing it from working. The agent must:
1. Diagnose all issues in the DOP/POP networks
2. Fix each error so the simulation runs
3. Cache at least 48 frames
4. Save the fixed scene

The task description does NOT reveal what the errors are — the agent must discover them.

## Injected Errors

| # | Error | Broken Value | Correct Range |
|---|-------|-------------|---------------|
| 1 | Gravity direction | forcey = +9.81 | -15 to -5 |
| 2 | Emission rate | birth_rate = 0 | > 0 |
| 3 | Collision path | `/obj/collision_geo/OUT` (missing) | Valid SOP path |
| 4 | DOP substeps | 0 | >= 1 |

## Success Criteria

| Criterion | Points | Key |
|-----------|--------|-----|
| Output scene exists and > 10KB | 5 | `output_exists`, `output_size_bytes` |
| Gravity fixed (negative Y, -15 to -5) | 20 | `gravity_forcey` |
| Emission rate fixed (> 0) | 20 | `birth_rate` |
| Collision path valid | 20 | `collision_path_valid` |
| Substeps fixed (>= 1) | 15 | `substeps` |
| Particles simulated (count > 0) | 10 | `particle_count_frame24/48` |
| At least 48 frames cached | 10 | `cached_frames` |
| **Total** | **100** | |
| **Pass threshold** | **60** | |

## Strategy Enumeration (Anti-Pattern 13)

| Strategy | Scene | Gravity | Emission | Collision | Substeps | Particles | Cache | Score | Pass? |
|----------|-------|---------|----------|-----------|----------|-----------|-------|-------|-------|
| Do-nothing (no save) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** | No |
| Re-save only | 5 | 0 | 0 | 0 | 0 | 0 | 0 | **5** | No |
| Fix gravity only | 5 | 20 | 0 | 0 | 0 | 0 | 0 | **25** | No |
| Fix gravity+emission+substeps | 5 | 20 | 20 | 0 | 15 | 10 | 10 | **80** | Yes |
| Fix all 4 errors | 5 | 20 | 20 | 20 | 15 | 10 | 10 | **100** | Yes |

Note: Fixing 3 of 4 errors (80 pts) scores a pass — this is acceptable since the agent has done substantial diagnostic work. Mass-action is not applicable to this error-injection pattern (there is no single action that fixes all errors).

## Partial Credit Check (Anti-Pattern 4)

Max partial total = 2 (scene small) + 10 (gravity partial) + 0 + 5 (collision changed) + 0 + 0 + 2 (minimal cache) = **19 < 60 threshold**

## Verification Strategy

`export_result.sh` uses hython to load the fixed scene and read back each parameter value directly, then attempts simulation to count particles and cached frames.

## Starting State

- Broken scene pre-loaded in Houdini with all 4 errors active
- Ground plane geometry exists at `/obj/ground_plane/OUT`
- Emitter geometry exists at `/obj/emitter_geo/raise_source`

## Features Used

DOP Network, POP Solver, POP Force, POP Collision Detect, POP Source, Simulation Caching
