# safety_parameters_commissioning

**Difficulty**: hard
**Environment**: qground_control_env
**Primary Occupation**: Drone Safety Officer / UAV Maintenance Technician

## Task Overview

A Drone Safety Officer must configure all 6 mandatory ArduPilot safety parameters before a new airframe is cleared for deployment. All parameters are at factory defaults (all of which are operationally unsafe). The agent reads the commissioning checklist to get the required values, then sets all 6 parameters via QGC's Vehicle Setup > Parameters interface.

## Domain Context

Pre-deployment commissioning is a legal and operational requirement for commercial UAV operations. Factory defaults for failsafe parameters are deliberately conservative or disabled — they assume the integrator will tune the vehicle before flight. Deploying an unconfigured vehicle risks fly-away, crash-on-battery-depletion, or uncontrolled behavior on link loss. This checklist-driven process is standard across ArduPilot-based fleets worldwide.

## Goal (End State)

All 6 parameters set to the values specified in `/home/ga/Documents/QGC/safety_checklist.txt`:

| Parameter | Required Value | Default | Meaning |
|-----------|---------------|---------|---------|
| FS_BATT_ENABLE | 2 | 0 | Land on low battery |
| RTL_ALT | 2500 | 1500 | Return at 25 m altitude |
| FENCE_ENABLE | 1 | 0 | Enable geofence |
| FENCE_ALT_MAX | 8000 | 10000 | 80 m altitude ceiling |
| FS_GCS_ENABLE | 1 | 0 | RTL on GCS heartbeat loss |
| LAND_SPEED_HIGH | 150 | 0 | 1.5 m/s high-altitude descent |

## Verification Strategy

`export_result.sh` queries ArduPilot SITL via pymavlink over TCP:5762 and writes a JSON with all 6 parameter values. The verifier reads the JSON and compares each value:
- Each correct parameter: 17 pts (first 4) or 16 pts (last 2) = 100 pts total
- Tolerances: ±0.4 for boolean/small integer params; ±10 for altitude/speed params

**Pass threshold**: 60 (requires ≥4 correct parameters)

## Anti-Gaming Analysis

| Strategy | Score | Pass? |
|----------|-------|-------|
| Do-nothing (all defaults) | 0 | No |
| 3 correct params | 51 | No |
| 4 correct params | 68 | Yes |
| All 6 correct | 100 | Yes |

All defaults differ from required values, so do-nothing always scores 0.

## Key Technical Details

- FENCE_ENABLE=0 ≠ FENCE_ENABLE=1 (tight tolerance 0.4 prevents match)
- FS_GCS_ENABLE=0 ≠ FS_GCS_ENABLE=1 (same)
- RTL_ALT stored in centimeters (2500 = 25m)
- FENCE_ALT_MAX stored in centimeters (8000 = 80m)
- Parameters take effect immediately when set via QGC (MAVLink PARAM_SET)

## Files

- `task.json`: Task definition, 60 steps, 480s timeout
- `setup_task.sh`: Creates `safety_checklist.txt`, resets all 6 params to defaults via pymavlink, ensures SITL+QGC running
- `export_result.sh`: Queries all 6 params via pymavlink, writes `/tmp/task_result.json`
- `verifier.py`: Reads JSON, checks each param value against required, scores per parameter
