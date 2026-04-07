# Task: Robot Workspace Sweep

## Domain Context
Robotics engineers perform workspace analysis as a critical step in production cell design. Before purchasing or deploying a robot arm, engineers must verify the robot's reachable workspace matches the spatial requirements of the production layout — e.g., reaching all assembly stations, avoiding interference zones. This task simulates that professional workflow.

## Goal
Characterize the reachable workspace envelope of a robot arm in CoppeliaSim by performing a systematic joint-space sweep, computing forward kinematics for each configuration, and exporting the workspace data to structured files.

## Difficulty: very_hard

## Required Output Files
1. `/home/ga/Documents/CoppeliaSim/exports/workspace_samples.csv`
   - Columns: sample_id, j0_deg, j1_deg, j2_deg, j3_deg, j4_deg, j5_deg, x_m, y_m, z_m, reach_radius_m, collision_free
   - Must contain >= 50 rows
2. `/home/ga/Documents/CoppeliaSim/exports/workspace_report.json`
   - Fields: total_samples, collision_free_count, max_reach_m, min_reach_m, mean_reach_m, workspace_volume_approx_m3

## Verification Strategy
- **Criterion 1 (20 pts)**: CSV file exists and was created after task start
- **Criterion 2 (25 pts)**: CSV has >= 50 sample rows
- **Criterion 3 (25 pts)**: Position data is spatially diverse (reach range >= 0.05m, >= 10 distinct positions)
- **Criterion 4 (30 pts)**: JSON report exists, is new, and contains required fields with total_samples >= 50

Pass threshold: 70/100

## Key Technical Notes
- ZMQ Remote API available on port 23000
- Python client: `/opt/CoppeliaSim/programming/zmqRemoteApi/clients/python/src`
- Robot arm with joints is loaded at task start
- `sim.getJointPosition()` / `sim.setJointPosition()` for joint control
- `sim.getObjectPosition(handle, -1)` returns position in world frame
- `sim.checkCollision(handle1, handle2)` for collision detection

## Anti-Gaming Notes
- Baseline: no output files exist before agent action
- Do-nothing score: 0 (no files → all criteria fail)
- Empty file: criteria 2,3 fail → score ≤ 45, below threshold
