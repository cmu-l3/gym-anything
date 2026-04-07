# Urban Flight Safety Configuration (`urban_flight_safety_config@1`)

## Overview
A Drone Safety Officer must configure ArduCopter failsafe and estimation parameters to safely operate in a high-magnetic-interference urban environment. The agent reads an operations brief, then tightens GPS tolerances, completely disables all magnetometers, changes the EKF heading source to GPS, and shortens the auto-disarm delay via QGroundControl's parameter editor.

## Rationale
**Why this task is valuable:**
- Tests the agent's ability to navigate, search, and modify values within QGroundControl's extensive parameter tree (~1000+ parameters).
- Evaluates document comprehension by requiring the agent to translate plain-text operational requirements into specific technical parameter variables.
- Exercises knowledge of drone safety systems, specifically Extended Kalman Filter (EKF) source selection and sensor gating.
- **Real-world Context:** Drones landing on urban rooftops or flying near steel bridges frequently experience catastrophic "flyaways." The massive amount of steel distorts the earth's magnetic field, confusing the drone's compass. Drone Safety Officers mitigate this by configuring the flight controller to ignore the compass entirely and rely on GPS kinematics for heading, while simultaneously enforcing much stricter GPS lock requirements before takeoff is permitted.

## Task Description

**Goal:** Configure 7 safety and navigation parameters in QGroundControl to prepare the vehicle for a rooftop delivery, matching the requirements specified in the urban operations brief.

**Starting State:** QGroundControl is running and connected to the ArduPilot SITL vehicle. All parameters are at their factory defaults. An operations brief is located at `/home/ga/Documents/QGC/urban_ops_brief.txt`.

**Expected Actions:**
1. Open and read the operations brief at `/home/ga/Documents/QGC/urban_ops_brief.txt` to discover the required parameter changes.
2. Navigate to QGroundControl's Vehicle Setup > Parameters interface.
3. Search for and configure the GPS quality thresholds:
   - Set Minimum Satellites (`GPS_SATS_MIN`) to **12**
   - Set Maximum HDOP (`GPS_HDOP_GOOD`) to **100** (representing 1.00)
4. Search for and disable all compass usage to prevent magnetic interference issues:
   - Set `COMPASS_USE` to **0**
   - Set `COMPASS_USE2` to **0**
   - Set `COMPASS_USE3` to **0**
5. Search for and update the EKF heading source:
   - Set `EK3_SRC1_YAW` to **2** (Configures EKF3 to use GPS instead of Compass)
6. Search for and shorten the ground safety delay:
   - Set `DISARM_DELAY` to **5** (seconds)

**Final State:** All 7 specified parameters are successfully modified and saved to the vehicle's flight controller.

## Verification Strategy

### Primary Verification: Live Parameter Query via MAVLink
The verifier script `export_result.sh` connects directly to the ArduPilot SITL instance using `pymavlink` over TCP port 5762. It requests the current values of all 7 target parameters and exports them to a JSON file (`/tmp/task_result.json`). The Python verifier reads this JSON and compares the live vehicle state against the required values.

### Secondary Verification: None Required
Because parameter changes take effect immediately on the ArduPilot SITL vehicle, querying the live MAVLink parameter state provides definitive proof of task completion. 

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| GPS Satellites | 15 | `GPS_SATS_MIN` equals 12 (Default is 6) |
| GPS HDOP | 15 | `GPS_HDOP_GOOD` equals 100 (Default is 140) |
| Compass 1 Disabled | 10 | `COMPASS_USE` equals 0 (Default is 1) |
| Compass 2 Disabled | 10 | `COMPASS_USE2` equals 0 (Default is 1) |
| Compass 3 Disabled | 10 | `COMPASS_USE3` equals 0 (Default is 1) |
| EKF3 Yaw Source | 20 | `EK3_SRC1_YAW` equals 2 (Default is 1) |
| Disarm Delay | 20 | `DISARM_DELAY` equals 5 (Default is 10) |
| **Total** | **100** | |

**Pass Threshold:** 70 points (Requires at least 5 of the 7 parameters to be correctly configured).
**Anti-Gaming:** Every required value differs from the ArduCopter factory default. A "do-nothing" agent will score 0 points.