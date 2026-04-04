# Incident Response Activation

## Domain Context

Following a security breach or facility incident, a rapid response team must restore full surveillance capability in a VMS system that has been left in a degraded state. This requires: auditing all cameras to identify coverage gaps, restoring recording on every affected camera, updating command personnel contact information to reflect incident response roles, provisioning a new incident commander account, and creating an all-cameras monitoring layout for the command center. This is a high-pressure, multi-domain task spanning camera management, user management, and layout management.

## Task Overview

**Difficulty**: very_hard
**Occupation context**: Incident Response Coordinator / Security Guard / Loss Prevention Manager

A multi-site security facility has suffered a breach and the overnight operations team has been disbanded. Cameras have been left in an unconfigured state. The agent must restore full surveillance capability.

The agent must independently:

1. **Identify and restore camera coverage** — Determine which cameras currently have recording disabled and enable 24/7 continuous recording on ALL cameras lacking it. The agent is NOT told which cameras need fixing.

2. **Update the night watch coordinator's contact** — The user `security.operator` has outdated information from the disbanded team. Update:
   - Full name → **`Night Watch Commander`**
   - Email → **`nightwatch@facility-security.com`**

3. **Provision incident commander account** — Create a new user:
   - Login: **`incident.cmdr`**
   - Full name: **`Incident Commander`**
   - Email: **`incident@facility-security.com`**
   - Role: **`Viewer`**

4. **Create incident command layout** — Create a layout named **`"Incident Command Center"`** containing ALL three cameras (Parking Lot Camera, Entrance Camera, Server Room Camera).

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Parking Lot Camera: 24/7 recording restored (`always` type, all 7 days) | 10 |
| Entrance Camera: 24/7 recording restored (`always` type, all 7 days) | 10 |
| Server Room Camera: 24/7 recording restored (`always` type, all 7 days) | 10 |
| `security.operator` full name updated to "Night Watch Commander" | 15 |
| `security.operator` email updated to "nightwatch@facility-security.com" | 15 |
| `incident.cmdr` user created with correct name and email | 20 |
| Layout "Incident Command Center" created | 5 |
| Layout contains all 3 cameras | 15 |
| **Total** | **100** |
| **Pass threshold** | **65** |

## Starting State

`setup_task.sh`:
- Disables recording on ALL cameras (agent must discover which cameras are affected — all of them)
- Resets `security.operator` to original name ("Security Operator") and email
- Removes `incident.cmdr` user if pre-existing
- Removes "Incident Command Center" layout if pre-existing

## Verification Strategy

`export_result.sh` queries via Nx Witness REST API:
- Each camera's recording schedule (`is_enabled`, `has_always`, `days_covered`)
- `security.operator` user's current `fullName` and `email`
- `incident.cmdr` user existence, `fullName`, `email`
- "Incident Command Center" layout existence and camera contents

Results written to `/tmp/incident_response_activation_result.json`.

`verifier.py` applies partial scoring per subtask. Camera restoration: 10 pts each (for a total of 30 pts). User update subtasks scored independently.

## Access Information

- **URL**: https://localhost:7001
- **Login**: admin / Admin1234!
- **API base**: https://localhost:7001/rest/v1/

## Edge Cases

- The very_hard difficulty: agent is NOT told how many cameras are affected or which ones — must check all cameras
- `security.operator` login is known, but the agent must locate and update a user by login name
- Layout `resourceId` values may include curly braces `{uuid}` — stripped before comparison
- Partial credit: each subtask independently scored; 65/100 threshold allows partial completion

## Schema Reference

```
GET /rest/v1/devices?type=Camera
  → [{id, name, schedule: {isEnabled, tasks: [{dayOfWeek, recordingType, fps}]}}]

PATCH /rest/v1/devices/{cameraId}
  → update schedule

GET /rest/v1/users
  → [{id, name, fullName, email, permissions}]

PATCH /rest/v1/users/{userId}
  → {fullName, email}  -- update user attributes

POST /rest/v1/users
  → {name, fullName, email, password, permissions}  -- create user

GET /rest/v1/layouts
  → [{id, name, items: [{resourceId}]}]

POST /rest/v1/layouts
  → {name, items: [{resourceId, ...}]}
```
