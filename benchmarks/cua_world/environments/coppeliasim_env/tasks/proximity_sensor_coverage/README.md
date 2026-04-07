# proximity_sensor_coverage

**Difficulty**: very_hard
**Timeout**: 900 seconds
**Occupation context**: Robotics Engineer — sensor placement optimization for safety systems

## Task Description

A robotics engineer must design and optimize the placement of a proximity sensor network for a robot workcell safety system. The engineer must programmatically create a proximity sensor in CoppeliaSim using the ZMQ Remote API, evaluate how much of a defined detection zone the sensor covers from multiple candidate placement positions, and produce a placement analysis report recommending the optimal sensor location.

The engineer must write a program that: creates a proximity sensor object in the scene, tests it from at least 5 distinct placement positions (varying x/y/z coordinates), measures the fraction of a defined target zone detected at each placement (coverage percentage), and writes two output files:

- `/home/ga/Documents/CoppeliaSim/exports/sensor_coverage.csv` — each row represents one candidate placement, with at minimum columns for the placement coordinates and a `coverage_pct` value (0.0–100.0)
- `/home/ga/Documents/CoppeliaSim/exports/sensor_analysis.json` — optimization report with fields: `total_placements`, `best_placement_id`, `best_coverage_pct`, `recommended_x`, `recommended_y`, `recommended_z`

## Scoring (100 pts, pass ≥ 70)

| Criterion | Points | Requirement |
|-----------|--------|-------------|
| CSV exists and is new | 20 | File created after task start |
| ≥ 5 placement rows in CSV | 25 | At least 5 candidate positions evaluated |
| Valid coverage percentages | 25 | Has coverage_pct column, ≥ 4 placements with values in [0, 100] |
| JSON report valid, ≥ 5 total_placements | 30 | All required fields present |

## Anti-gaming

- Output directory is cleared before the task starts; stale files score 0
- All files must have a modification time after the task start timestamp
- Do-nothing attempt scores 0 points
- Empty CSV with fake JSON scores at most 20 (fails 70 threshold)

## Technical Notes

- Scene: starts empty (agent constructs the sensor and test geometry from scratch)
- ZMQ Remote API: port 23000, `RemoteAPIClient()` from `/opt/CoppeliaSim/programming/zmqRemoteApi/clients/python/src`
- Create a proximity sensor: `sim.createProximitySensor(sensor_type, sub_type, options, int_params, float_params)`
- Set object position: `sim.setObjectPosition(handle, -1, [x, y, z])`
- Read sensor state: `sim.readProximitySensor(handle)` returns `(result, distance, detected_point, detected_handle, detected_normal)`
- To measure coverage, create a grid of test target points and count how many are detected by the sensor at each placement
- Start simulation with `sim.startSimulation()` before sensor reads; step with `sim.step()`
- Create output directory if it does not exist
