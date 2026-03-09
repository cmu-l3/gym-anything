# manage_user_roles

**Difficulty:** Hard
**Environment:** openclinica_env@0.1
**Task ID:** manage_user_roles@1

## Overview

A compliance audit has flagged several user access control issues in OpenClinica that must be remediated immediately. The agent must perform five independent user role management operations across three clinical studies, using the OpenClinica web interface (root / Admin123!).

## Subtasks

| # | Action | User | Study | Detail |
|---|--------|------|-------|--------|
| 1 | Change role | mrivera | DM-TRIAL-2024 (Phase II Diabetes Trial) | data_manager → monitor |
| 2 | Remove access | lchang | CV-REG-2023 (Cardiovascular Outcomes Registry) | Remove all active roles |
| 3 | Create user | kpatel | — | Kavya Patel, k.patel@clinical-research.org, Stanford Medical Center |
| 4 | Assign role | kpatel | DM-TRIAL-2024 (Phase II Diabetes Trial) | investigator |
| 5 | Assign role | mrivera | AP-PILOT-2022 (Asthma Prevention Pilot) | monitor |

## Scoring (100 points total)

| Criterion | Points |
|-----------|--------|
| mrivera DM Trial role is 'monitor' | 20 |
| lchang has no active role in CV Registry | 20 |
| kpatel user account exists with correct details | 25 |
| kpatel has 'investigator' role in DM Trial | 20 |
| mrivera has 'monitor' role in AP Pilot | 15 |
| VLM visual check (user management UI visible) | up to 10 |
| Audit log penalty (no GUI interaction detected) | -20 |

**Pass threshold:** 70 points

## Files

- `task.json` — Task definition and metadata
- `setup_task.sh` — Pre-task setup: seeds initial role state, removes kpatel for clean run, records baselines
- `export_result.sh` — Post-task export: queries DB for all five subtask outcomes, writes `/tmp/manage_user_roles_result.json`
- `verifier.py` — Scoring logic with nonce integrity check and VLM visual verification

## Setup State (after setup_task.sh runs)

- mrivera has `data_manager` role in DM Trial (must be changed to `monitor`)
- lchang has `monitor` role in CV Registry (must be removed)
- kpatel does NOT exist in user_account (must be created)
- mrivera has NO role in AP Pilot (must be assigned `monitor`)

## DB Tables Used

- `user_account` — user creation and lookup
- `study_user_role` — role assignment, modification, and removal
- `study` — resolved via `unique_identifier` field (DM-TRIAL-2024, CV-REG-2023, AP-PILOT-2022)

## Notes

- OpenClinica may require removing an existing role entry and re-inserting with the new role name, rather than in-place editing.
- Role names in the DB use underscores: `data_manager`, `monitor`, `investigator`, `coordinator`, `crc`.
- The verifier uses case-insensitive substring matching to handle minor formatting differences in role names.
