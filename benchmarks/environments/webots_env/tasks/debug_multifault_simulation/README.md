# Task: Debug Multi-Fault Simulation

## Overview

**Difficulty**: Very Hard
**Occupation**: Senior Robotics Simulation Engineer / Robotics QA Engineer
**Industry**: Robotics Systems / Simulation Engineering
**Environment**: Webots 3D Robot Simulator

## Domain Context

Senior robotics simulation engineers frequently review simulation worlds submitted by junior team members or imported from external sources. A common workflow is to audit a submitted world for configuration errors before approving it for use in test pipelines. This requires domain knowledge to recognize that physics is configured incorrectly (zero gravity, invalid mass), and simulation performance is degraded (too-slow timestep).

This task represents a "world audit" scenario where the engineer must identify and correct all errors without being given a list of what to look for. The errors span multiple distinct aspects of the Webots world configuration.

## Task Goal

**Open the simulation, identify all configuration errors, fix them, and save the corrected world.**

No list of errors is provided. The engineer must:
1. Examine the WorldInfo node for simulation accuracy settings
2. Inspect robot Physics nodes for invalid mass configurations
3. Assess whether the physics environment is correctly set up for real-world conditions

Save the corrected world to **`/home/ga/Desktop/fixed_simulation.wbt`**

## Planted Errors (Ground Truth — NOT shown to agent)

The `soccer.wbt` starting world has been modified with three distinct errors:

1. **`WorldInfo.basicTimeStep = 256`** — Far too slow for robot simulation (should be ≤64ms for accurate soccer robot control)
2. **`WorldInfo.gravity = 0.0`** — Zero gravity makes the simulation non-physical for an Earth-based robot scenario (should be ≈9.81 m/s²)
3. **`BLUE_PLAYER_1` Physics mass = 0.0** — A robot with zero mass has undefined physics behavior and will float/behave incorrectly (mass must be positive)

## Success Criteria

The saved world at `/home/ga/Desktop/fixed_simulation.wbt` must contain:
1. File exists at correct path — 10 points
2. `basicTimeStep` ≤ 64 (any value from 8 to 64 is acceptable) — 30 points
3. `gravity` ≥ 9.0 (Earth-range gravity) — 30 points
4. All robot Physics mass values > 0.1 kg — 30 points

**Pass threshold**: 70/100 points

Note: The agent receives credit if it corrects any combination of errors. Partial credit is awarded for each independently fixed error.

## Verification Strategy

The verifier:
1. Copies the saved `.wbt` file from the VM
2. Extracts the `basicTimeStep` value from WorldInfo
3. Extracts the `gravity` value from WorldInfo
4. Finds all `Physics { ... mass X ... }` blocks and checks all mass values are positive

## Features Exercised

| Feature | Description |
|---------|-------------|
| WorldInfo basicTimeStep | Understand simulation timestep requirements |
| WorldInfo gravity | Recognize and correct physics environment |
| Robot Physics mass | Find and fix robot body mass configuration |
| Scene tree navigation | Navigate to WorldInfo and individual robot nodes |
| Domain knowledge | Recognize which values are physically unrealistic |
| File > Save World As | Save modified world to specific path |

## Why This Task is Very Hard

- No specific errors are identified for the agent — it must discover them
- The errors span three different parts of the world (WorldInfo ×2 and robot Physics)
- Recognizing the errors requires domain knowledge of simulation physics
- The agent must make judgment calls about what "correct" values should be (e.g., choosing a valid timestep between 8 and 64ms)
