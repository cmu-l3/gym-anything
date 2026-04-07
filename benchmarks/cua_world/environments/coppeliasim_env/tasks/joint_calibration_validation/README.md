# joint_calibration_validation

**Difficulty**: very_hard
**Timeout**: 900 seconds
**Occupation context**: Robotics Engineer — robot arm calibration and quality validation

## Task Description

A robotics engineer must perform a calibration validation study on a robot arm. After physical calibration, the engineer must verify that the robot's forward kinematics model matches actual end-effector positions across a range of joint configurations. The study involves commanding the arm to multiple joint configurations spanning a wide range of motion, recording the commanded joint angles and the resulting measured Cartesian end-effector positions, computing position errors, and flagging configurations that exceed a tolerance threshold.

The engineer must write a program that commands the robot to at least 10 diverse joint configurations (spanning at least 60° of range in at least one joint), records both the commanded configuration and the measured end-effector position, computes per-configuration position errors, and writes two output files:

- `/home/ga/Documents/CoppeliaSim/exports/calibration_results.csv` — each row represents one tested configuration, with columns including measured end-effector position (`measured_x`, `measured_y`, `measured_z`) and `position_error_mm`
- `/home/ga/Documents/CoppeliaSim/exports/calibration_report.json` — summary with fields: `total_configs`, `flagged_count`, `max_error_mm`, `pass_rate_pct`

## Scoring (100 pts, pass ≥ 70)

| Criterion | Points | Requirement |
|-----------|--------|-------------|
| CSV exists and is new | 20 | File created after task start |
| ≥ 10 configuration rows in CSV | 25 | At least 10 joint configurations tested |
| Positions + errors, wide joint range | 25 | Has measured_x/y/z and position_error_mm columns, ≥ 8 configs with error data, ≥ 60° joint range |
| JSON report valid, ≥ 10 total_configs | 30 | All required fields present |

## Anti-gaming

- Output directory is cleared before the task starts; stale files score 0
- All files must have a modification time after the task start timestamp
- Do-nothing attempt scores 0 points
- Empty CSV with fake JSON scores at most 20 (fails 70 threshold)

## Technical Notes

- Scene: `messaging/movementViaRemoteApi.ttt`
- ZMQ Remote API: port 23000, `RemoteAPIClient()` from `/opt/CoppeliaSim/programming/zmqRemoteApi/clients/python/src`
- Use `sim.setStepping(True)` and `sim.step()` for deterministic control
- Set joint positions with `sim.setJointTargetPosition(joint_handle, angle_radians)`
- Read end-effector position with `sim.getObjectPosition(tip_handle, -1)`
- Position error is the Euclidean distance (mm) between expected FK position and measured position
- Create output directory if it does not exist
