# Task: Deploy Swarm Experiment

## Overview

**Difficulty**: Very Hard
**Occupation**: Swarm Robotics Researcher / Multi-Robot Systems Engineer
**Industry**: Academic Research / Warehouse Automation / Swarm Robotics
**Environment**: Webots 3D Robot Simulator

## Domain Context

Swarm robotics researchers use Webots to simulate coordinated multi-robot behavior before physical deployment. When preparing a multi-robot experiment, the world configuration must be correct for ALL robots simultaneously: each robot needs a working controller, the robots cannot start in colliding positions, and the simulation physics must run fast enough for real-time behavior evaluation.

This task represents a common lab scenario: a colleague has submitted a world file "ready for the experiment" but when you inspect it, it cannot actually run correctly. The researcher must identify and fix all issues across the multi-robot setup without being given a checklist of problems.

## Task Goal

**Audit the multi-robot Webots world, identify all configuration problems, fix them, and save a working world.**

The world is based on the Webots soccer demo. Use your knowledge of the soccer demo environment's available controllers to configure the robots appropriately.

Save the corrected world to **`/home/ga/Desktop/swarm_ready.wbt`**

## Planted Errors (Ground Truth — NOT shown to agent)

Three distinct types of errors have been introduced:

1. **All soccer player robot controllers set to `"soccer_player_broken"`** — This controller does not exist, so none of the robots will execute any behavior. The correct controller for soccer players in this world is `"soccer_player"`.

2. **All 4 soccer player robots positioned at the same coordinates** — All robots start at the same position, causing immediate collision detection failures and unrealistic behavior when the simulation starts.

3. **`WorldInfo.basicTimeStep = 128`** — This timestep is too slow for soccer robot control (soccer players need ≤64ms timestep for proper physics and responsive control).

## Success Criteria

The saved world at `/home/ga/Desktop/swarm_ready.wbt` must contain:
1. File exists at correct path — 10 points
2. At least 3 robots with controller ≠ `"soccer_player_broken"` and ≠ `"<none>"` — 30 points
3. At least 2 robot pairs with distinct, non-overlapping translations (distance > 0.15m) — 30 points
4. `basicTimeStep` ≤ 64 — 30 points

**Pass threshold**: 70/100 points

## Verification Strategy

The verifier:
1. Copies the saved `.wbt` file from the VM
2. Finds all `controller "..."` values in robot nodes
3. Counts how many have controllers other than `"soccer_player_broken"` and `"<none>"`
4. Extracts all robot translation values and checks for spatial diversity
5. Checks the `basicTimeStep` value

## Features Exercised

| Feature | Description |
|---------|-------------|
| Multi-robot scene tree | Navigate and modify multiple robot nodes |
| Controller assignment | Fix controller names on multiple robots |
| Robot translation editing | Reposition multiple robots to non-overlapping locations |
| WorldInfo basicTimeStep | Fix simulation timestep |
| File exploration | Find available controllers in the controllers directory |
| Domain knowledge | Know which controllers are valid for soccer robots |
| File > Save World As | Save modified world to specific path |

## Why This Task is Very Hard

- No errors are explicitly identified — the agent must discover them by inspection
- Three distinct types of errors exist (controller, position, timestep)
- The agent must know or discover the correct controller name (`soccer_player`)
- Fixing all robots requires multiple independent scene tree operations
- The agent must space out 4+ robots to non-overlapping positions (spatial reasoning)
