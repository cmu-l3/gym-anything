# assembly_timing_analysis

**Difficulty**: very_hard
**Timeout**: 900 seconds
**Occupation context**: Robotics Engineer — industrial assembly line optimization

## Task Description

A robotics engineer is tasked with benchmarking the cycle time of an automated pick-and-place assembly cell to identify throughput bottlenecks. The simulation is running a pick-and-place demonstration. The engineer must instrument the simulation to capture per-cycle timing data, run the cell through at least 10 full pick-and-place cycles, and produce a timing report used by production engineering to set OEE targets.

The engineer must write a control program that runs the simulation, measures the wall-clock duration of each pick-and-place cycle, and writes two output files:

- `/home/ga/Documents/CoppeliaSim/exports/cycle_timing.csv` — each row represents one cycle with at minimum a `cycle_id` and `cycle_duration_s` column (positive float, seconds)
- `/home/ga/Documents/CoppeliaSim/exports/timing_report.json` — summary with fields: `total_cycles`, `avg_cycle_time_s`, `min_cycle_time_s`, `max_cycle_time_s`, `throughput_cph` (cycles per hour)

## Scoring (100 pts, pass ≥ 70)

| Criterion | Points | Requirement |
|-----------|--------|-------------|
| CSV exists and is new | 20 | File created after task start |
| ≥ 10 cycle rows in CSV | 25 | At least 10 measured cycles |
| Valid timing data | 25 | ≥ 8 rows with positive duration, avg in (0, 300] s |
| JSON report valid, ≥ 10 total_cycles | 30 | All required fields present and plausible |

## Anti-gaming

- Output directory is cleared before the task starts; stale files score 0
- All files must have a modification time after the task start timestamp
- Do-nothing attempt scores 0 points
- Empty CSV with fake JSON scores at most 20 (fails 70 threshold)

## Technical Notes

- Scene: `pickAndPlaceDemo.ttt`
- ZMQ Remote API: port 23000, `RemoteAPIClient()` from `/opt/CoppeliaSim/programming/zmqRemoteApi/clients/python/src`
- Use `sim.setStepping(True)` and `sim.step()` for deterministic simulation stepping
- Use Python `time.time()` to record wall-clock cycle start/end timestamps
- A "cycle" is one complete pick (grasp object) → transport → place → return sequence
- The demo scene's robot logic runs inside the scene; the engineer monitors via API callbacks or object position polling to detect cycle boundaries
- Create output directory if it does not exist
