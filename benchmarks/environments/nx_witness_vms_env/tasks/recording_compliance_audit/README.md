# Recording Compliance Audit

## Domain Context

Security guards and loss prevention managers in retail and commercial facilities are required by company policy and sometimes by law (e.g., insurance requirements, PCI-DSS compliance) to maintain continuous 24/7 video recording on all surveillance cameras. When recording schedules are misconfigured or accidentally disabled — e.g., after a system update, a power outage, or staff error — cameras silently stop recording, creating coverage gaps that are discovered only after an incident occurs. Performing a compliance audit means checking every camera's recording status and restoring continuous recording wherever it is missing.

## Task Overview

**Difficulty**: very_hard
**Occupation context**: Loss Prevention Manager / Security Management Specialist

The VMS system has been running for several weeks but recording schedules have not been verified recently. Some cameras may be recording and some may not. The agent must:

1. Audit all cameras in the system to determine which ones currently have recording enabled and which do not
2. Enable 24/7 continuous recording on **every camera that currently lacks it** — the agent is NOT told which cameras need fixing
3. Create a layout named **"Compliance Audit View"** containing all three cameras (Parking Lot Camera, Entrance Camera, Server Room Camera)

The agent must determine independently which cameras need intervention by inspecting recording schedules.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Parking Lot Camera has 24/7 continuous recording enabled (all 7 days, `always` type) | 25 |
| Server Room Camera has 24/7 continuous recording enabled (all 7 days, `always` type) | 25 |
| Entrance Camera has continuous recording enabled (may already be configured) | 10 |
| Layout "Compliance Audit View" exists | 10 |
| Layout contains all 3 cameras | 30 |
| **Total** | **100** |
| **Pass threshold** | **60** |

## Starting State

`setup_task.sh` disables recording on 2 of the 3 cameras (Parking Lot and Server Room) and leaves Entrance Camera enabled. The agent does not know this in advance — it must audit all cameras to discover the situation.

## Verification Strategy

`export_result.sh` queries each camera's recording schedule via the Nx Witness REST API (`/rest/v1/devices`), checking `schedule.isEnabled`, `schedule.tasks[].recordingType`, and day coverage. It also checks for the "Compliance Audit View" layout and verifies which cameras it contains. Results are written to `/tmp/recording_compliance_audit_result.json`.

`verifier.py` reads the JSON and scores:
- Per-camera recording: checks `is_enabled=True`, `has_always=True`, `days_covered>=7`
- Layout existence and camera membership

## Access Information

- **URL**: https://localhost:7001
- **Login**: admin / Admin1234!
- **API base**: https://localhost:7001/rest/v1/

## Edge Cases

- Camera IDs contain curly braces (`{uuid}`) in some API responses — the export script strips these before comparison
- The agent should NOT rely on camera display order or pre-knowledge of which cameras need fixing
- A layout "Compliance Audit View" must be NEWLY created (not pre-existing) — setup ensures none exists before the task

## Schema Reference

```
GET /rest/v1/devices?type=Camera
  → [{id, name, schedule: {isEnabled, tasks: [{dayOfWeek, recordingType, fps, streamQuality}]}}]

GET /rest/v1/layouts
  → [{id, name, items: [{resourceId}]}]

POST /rest/v1/layouts
  → create new layout

PATCH /rest/v1/devices/{id}
  → update camera schedule
```
