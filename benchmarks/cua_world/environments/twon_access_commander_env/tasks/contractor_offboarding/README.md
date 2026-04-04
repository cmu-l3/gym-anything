# Task: contractor_offboarding

## Domain Context

Security Management Specialists in commercial office buildings routinely offboard vendor contractor staff when contracts are terminated. Per standard access control policy, terminated contractors must be disabled in the PACS — records are retained for audit but access must be revoked immediately.

## Goal

All users associated with the terminated vendor "Meridian Facilities" must be offboarded:
1. Each Meridian Facilities account must be **disabled** (not deleted — records must be kept for audit).
2. All **RFID card and PIN credentials** must be revoked from each disabled account.

The agent is not told which users belong to Meridian Facilities — it must discover them by inspecting the system.

## Starting State

Three contractor users from Meridian Facilities exist with active accounts and RFID cards:
- Nadia Ivanova (card 0004521890)
- Tomás Guerrero (card 0004521891)
- Olumide Adeyemi (card 0004521892)

All three are enabled and in the "Contractors" group.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Each Meridian user account is disabled | 10 pts × 3 = 30 pts |
| Each Meridian user has 0 credentials | 15 pts × 3 = 45 pts |
| All 3 Meridian users still exist (not deleted) | 10 pts |
| No non-Meridian user collaterally disabled | 15 pts |
| **Pass threshold** | **70 pts** |

## Verification Strategy

`export_result.sh` queries the AC REST API for all users, separates them by company, and records enabled status + credential count for each Meridian user. `verifier.py` applies the 4-criterion scoring above.

## Files

- `task.json` — Task specification (difficulty: very_hard)
- `setup_task.sh` — Resets 3 Meridian users to enabled+credentialed state
- `export_result.sh` — Queries all users and their credentials post-task
- `verifier.py` — Scores 4 independent criteria
