# Task: setup_release_pipeline_repos

## Summary
Set up a complete Maven artifact management pipeline in JFrog Artifactory for a fintech microservices architecture, involving 5 independently-verifiable deliverables across repository management, team administration, and access control.

## Occupation Context
- **Role**: DevOps Engineer / Platform Engineer
- **Industry**: Financial Technology (Fintech)
- **Realistic scenario**: A payments startup adopting microservices needs Artifactory configured before enabling CI/CD pipelines. All 5 requirements must be in place simultaneously before any pipeline runs.

## Difficulty: very_hard
This task chains 5 distinct Artifactory feature areas that must be completed in the right dependency order:
1. Create a local Maven repository (`ms-releases`)
2. Create a remote Maven proxy (`maven-central-proxy`) — references an external URL
3. Create a virtual Maven repository (`ms-build-virtual`) — references both repos above
4. Create a group (`build-engineers`)
5. Create a permission target (`build-access`) — references both the repo and the group

The agent must discover the correct creation order (virtual after local+remote; permission after group+repo) and navigate 4+ distinct admin sections of the Artifactory UI without being told which menus to use.

## Verification Criteria (100 pts total, pass ≥ 60)
| # | Criterion | Points |
|---|-----------|--------|
| 1 | `ms-releases` exists as LOCAL Maven repository | 20 |
| 2 | `maven-central-proxy` exists as REMOTE Maven repo pointing to Maven Central | 20 |
| 3 | `ms-build-virtual` exists as VIRTUAL Maven repo including both ms-releases and maven-central-proxy | 20 |
| 4 | `build-engineers` group exists | 20 |
| 5 | `build-access` permission grants `build-engineers` Deploy+Read on `ms-releases` | 20 |

## Setup Behavior
`setup_task.sh` performs idempotent cleanup:
- Deletes `ms-build-virtual`, `ms-releases`, `maven-central-proxy`, `build-access`, `build-engineers` if present
- Records initial repo count to `/tmp/initial_repo_count`
- Navigates Firefox to the Repositories admin page as the agent's starting view

## Verification Method
`verifier.py` uses Artifactory's REST GET API via `exec_capture`:
- `GET /api/repositories` — confirms repo existence, type, packageType
- `GET /api/repositories/{key}` — confirms remote URL for criterion 2
- `GET /api/security/groups/build-engineers` — confirms group existence
- `GET /api/security/permissions/build-access` — confirms repos, group assignment, privileges

## Do-Nothing Score: 0
All 5 target entities are deleted by `setup_task.sh` before the agent starts. A do-nothing agent scores 0.
