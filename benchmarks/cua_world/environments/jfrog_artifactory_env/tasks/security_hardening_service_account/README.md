# Task: security_hardening_service_account

## Summary
Remediate 5 SOC-2 compliance findings by replacing an over-privileged long-lived admin credential used by CI/CD pipelines with a properly scoped service account, group, repository, permission, and access token.

## Occupation Context
- **Role**: Platform Security Engineer
- **Industry**: Healthcare / Life Sciences
- **Realistic scenario**: A quarterly security audit in a healthcare software company found CI/CD pipelines authenticating as the Artifactory admin user. This violates SOC-2 and HIPAA security control requirements, triggering a mandatory remediation with 5 specific findings that must all be closed.

## Difficulty: very_hard
The agent must chain 6 distinct Artifactory operations spanning 4 different admin sections:
1. Create a non-admin user account (`Security → Users`)
2. Create a group (`Security → Groups`)
3. Assign the user to the group (editing group membership)
4. Create a local npm repository (`Repositories`)
5. Create a permission target (`Security → Permissions`) referencing the group and repo
6. Generate an access token for the service user (`Security → Access Tokens`)

The dependency graph is non-trivial: the permission cannot be created before both the group and the repo exist; the access token must be for the service user (not admin); group membership requires the user and group to both exist first.

## Verification Criteria (100 pts total, pass ≥ 60)
| # | Criterion | Points |
|---|-----------|--------|
| 1 | `svc-deploy` user exists, non-admin, email matches `apex-healthcare.com` | 20 |
| 2 | `ci-services` group exists and `svc-deploy` is a member | 20 |
| 3 | `npm-builds` local npm repository exists | 20 |
| 4 | `svc-deploy-perms` permission grants `ci-services` Deploy+Read on `npm-builds` | 20 |
| 5 | Access token with description "Service account token - Q1 2026 rotation" exists | 20 |

## Setup Behavior
`setup_task.sh` performs idempotent cleanup:
- Deletes `svc-deploy-perms` permission, `svc-deploy` user, `ci-services` group, `npm-builds` repo
- Revokes any existing tokens matching "Q1 2026 rotation" in description
- Navigates Firefox to the Users admin page

## Verification Method
`verifier.py` queries:
- `GET /api/security/users/svc-deploy` — confirms user existence, admin=false, email
- `GET /api/security/groups/ci-services` — confirms group, checks `userNames` for svc-deploy membership
- `GET /api/repositories` — confirms npm-builds as LOCAL npm type
- `GET /api/security/permissions/svc-deploy-perms` — confirms repos, group privileges
- `GET /access/api/v1/tokens` — searches by description for the rotation token

## Do-Nothing Score: 0
All 5 target entities are deleted by `setup_task.sh` before the agent starts.
