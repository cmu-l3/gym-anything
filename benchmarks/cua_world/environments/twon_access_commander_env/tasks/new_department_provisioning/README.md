# Task: new_department_provisioning

## Domain Context

IT security administrators routinely provision access control infrastructure for new operational areas. This involves creating user groups, time profiles, enrolling existing staff, and onboarding new personnel — a multi-step workflow chaining several distinct PACS features.

## Goal

Provision a new "Executive Operations" floor in the access control system:

1. Create a group named **"Executive Operations"**
2. Create a time profile named **"Executive Hours"** (Monday–Friday, 07:00–22:00)
3. Add all current **IT Department** members to "Executive Operations" (they need cross-floor access for infrastructure support). The agent must discover who is in IT Department.
4. Create a new user **Elena Vasquez** (e.vasquez@buildingtech.com, +1-312-555-0300, BuildingTech Solutions), assign her RFID card **0004522050**, and add her to "Executive Operations".

## Starting State

Clean slate — `setup_task.sh` removes any prior "Executive Operations" group, "Executive Hours" time profile, and Elena Vasquez user.

IT Department members (to be discovered by agent):
- Kwame Asante (k.asante@buildingtech.com)
- Mei-Ling Zhang (m.zhang@buildingtech.com)

## Success Criteria

| Criterion | Points |
|-----------|--------|
| "Executive Operations" group created | 15 pts |
| "Executive Hours" profile with Mon-Fri 07:00-22:00 | 20 pts |
| Kwame Asante in Executive Operations | 15 pts |
| Mei-Ling Zhang in Executive Operations | 15 pts |
| Elena Vasquez user exists (correct email) | 15 pts |
| Elena has card 0004522050 | 10 pts |
| Elena in Executive Operations | 10 pts |
| **Pass threshold** | **70 pts** |

## Verification Strategy

`export_result.sh` checks all 7 sub-criteria: group existence + member list, time profile schedule, Elena's user record, credentials, and group membership. `verifier.py` applies partial credit for close-but-not-exact time profile schedules.

## Files

- `task.json` — Task specification (difficulty: very_hard)
- `setup_task.sh` — Removes prior state, verifies IT Department integrity
- `export_result.sh` — Queries group, time profile, and user state post-task
- `verifier.py` — Scores 7 criteria with partial credit on time profile
