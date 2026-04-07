# ik_weld_trajectory

**Difficulty**: very_hard
**Timeout**: 900 seconds
**Occupation context**: Robotics Engineer — industrial welding automation

## Task Description

A robotics engineer has been tasked with programming a robotic welding cell. The robot arm must follow a linear weld seam along a workpiece using inverse kinematics. The engineer must write a control program that drives the arm through a series of waypoints covering a minimum weld length, records the actual achieved end-effector positions at each waypoint, and exports a structured report for quality assurance review.

The robot arm is loaded in a simulation. The engineer must use the ZMQ Remote API to command joint positions that achieve target Cartesian end-effector poses along the weld path, record actual achieved positions, and write two output files:

- `/home/ga/Documents/CoppeliaSim/exports/weld_trajectory.csv` — each row represents one waypoint with at minimum columns for actual end-effector position (e.g., `actual_x`, `actual_y`, `actual_z`) and a `reached` flag
- `/home/ga/Documents/CoppeliaSim/exports/weld_stats.json` — summary report with fields: `total_waypoints`, `reached_count`, `path_length_m`, `weld_start_xyz`, `weld_end_xyz`

## Scoring (100 pts, pass ≥ 70)

| Criterion | Points | Requirement |
|-----------|--------|-------------|
| CSV exists and is new | 20 | File created after task start |
| ≥ 8 waypoints in CSV | 25 | At least 8 rows of position data |
| Path spans ≥ 0.2 m in XY plane | 25 | End-effector covers sufficient weld length |
| JSON stats valid, ≥ 8 total_waypoints | 30 | All required fields present |

## Anti-gaming

- Output directory is cleared before the task starts; stale files score 0
- All files must have a modification time after the task start timestamp
- Do-nothing attempt scores 0 points
- Empty files with no rows score at most 20 (fails threshold of 70)

## Technical Notes

- Scene: `messaging/movementViaRemoteApi.ttt`
- ZMQ Remote API: port 23000, `RemoteAPIClient()` from `/opt/CoppeliaSim/programming/zmqRemoteApi/clients/python/src`
- Use `sim.setStepping(True)` and `sim.step()` for deterministic simulation control
- Get joint handles with `sim.getObject('/joint_name')`
- Read end-effector position with `sim.getObjectPosition(tip_handle, -1)`
- Create output directory if it does not exist
